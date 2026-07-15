[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot '..\starter'),
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-LoopbackEndpoint([string]$Endpoint) {
  if ([string]::IsNullOrEmpty($Endpoint) -or $Endpoint.IndexOf([char]13) -ge 0 -or $Endpoint.IndexOf([char]10) -ge 0) {
    throw 'LocalstackEndpoint must not contain CR or LF.'
  }
  $uri = $null
  $match = [regex]::Match($Endpoint, '\Ahttp://(?:localhost|127\.0\.0\.1):(?<port>[1-9][0-9]{0,4})\z')
  if (-not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or
    -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
    $uri.DnsSafeHost -notin @('localhost', '127.0.0.1') -or $uri.PathAndQuery -ne '/' -or
    -not [string]::IsNullOrEmpty($uri.UserInfo)) {
    throw 'LocalstackEndpoint must be a loopback HTTP root origin with an explicit port from 1 to 65535.'
  }
}

function Invoke-Terraform([string[]]$Arguments, [int[]]$Expected = @(0)) {
  $old = $ErrorActionPreference
  try { $ErrorActionPreference = 'Continue'; $output = @(& terraform @Arguments 2>&1); $code = $LASTEXITCODE }
  finally { $ErrorActionPreference = $old }
  $output | ForEach-Object { Write-Host $_ }
  if ($code -notin $Expected) { throw "terraform $($Arguments -join ' ') exited $code." }
  return [pscustomobject]@{ ExitCode = $code; Output = $output }
}

function Invoke-Aws([string[]]$Arguments) {
  $old = $ErrorActionPreference
  try { $ErrorActionPreference = 'Continue'; $output = @(& aws @Arguments 2>&1); $code = $LASTEXITCODE }
  finally { $ErrorActionPreference = $old }
  if ($code -ne 0) { throw "aws $($Arguments -join ' ') exited $code`: $($output -join ' ')" }
  return ($output -join "`n").Trim()
}

function Read-Plan([string]$Path) {
  $result = Invoke-Terraform @('show', '-json', $Path)
  return (($result.Output -join "`n") | ConvertFrom-Json)
}

function Assert-Plan([object]$Plan, [string[]]$Addresses, [string]$Action) {
  $changed = @($Plan.resource_changes | Where-Object { (@($_.change.actions) -join ',') -ne 'no-op' })
  $actual = @($changed | ForEach-Object { $_.address } | Sort-Object)
  $expected = @($Addresses | Sort-Object)
  if (($actual -join "`n") -ne ($expected -join "`n")) { throw "Plan addresses differ: $($actual -join ', ')." }
  foreach ($item in $changed) {
    if ((@($item.change.actions) -join ',') -ne $Action -or $item.type -ne 'aws_s3_bucket') {
      throw "Unexpected plan action/type at $($item.address)."
    }
  }
}

function Assert-Candidate([string]$Root) {
  $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.tf')
  if ($files.Count -ne 9) { throw 'Candidate must contain the exact root and child-module HCL file set.' }
  if (@(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1').Count -ne 0) { throw 'Candidate scripts are out of scope.' }
  $text = ($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
  if ($text -match '(?i)TODO|mock_provider|override_') { throw 'Candidate is unfinished or uses unsupported test constructs.' }
  if ([regex]::Matches($text, '(?m)^provider\s+"aws"\s*\{').Count -ne 2 -or
      [regex]::Matches($text, '(?m)^\s*alias\s*=\s*"(primary|recovery)"').Count -ne 2) {
    throw 'Root must contain exactly two explicitly aliased AWS providers.'
  }
  foreach ($pattern in @(
    'access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"',
    'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true',
    'skip_requesting_account_id\s*=\s*true', 's3_use_path_style\s*=\s*true',
    's3\s*=\s*var\.localstack_endpoint', 'sts\s*=\s*var\.localstack_endpoint'
  )) {
    if ([regex]::Matches($text, $pattern).Count -ne 2) { throw "Provider contract mismatch: $pattern" }
  }
  if ($text -notmatch 'configuration_aliases\s*=\s*\[\s*aws\.primary\s*,\s*aws\.recovery' -or
      $text -notmatch 'aws\.primary\s*=\s*aws\.primary' -or $text -notmatch 'aws\.recovery\s*=\s*aws\.recovery') {
    throw 'Provider slots and root mappings must be explicit and correctly aligned.'
  }
  $resources = @([regex]::Matches($text, '(?m)^\s*resource\s+"([^"]+)"\s+"([^"]+)"') | ForEach-Object { "$($_.Groups[1].Value).$($_.Groups[2].Value)" })
  if (($resources | Sort-Object) -join ',' -ne 'aws_s3_bucket.primary,aws_s3_bucket.recovery') { throw 'Only the two required S3 bucket resources are allowed.' }
  if ([regex]::Matches($text, 'data\s+"aws_caller_identity"').Count -ne 2) { throw 'Each provider slot must query caller identity.' }
}

Assert-LoopbackEndpoint $LocalstackEndpoint
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw 'terraform is required.' }

$original = (Get-Location).Path
$lab = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c11-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $scratch 'candidate'
$prefix = 'c11-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$variables = @("-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint")
$addresses = @('module.replicated_storage.aws_s3_bucket.primary', 'module.replicated_storage.aws_s3_bucket.recovery')
$primaryBucket = "$prefix-primary"
$recoveryBucket = "$prefix-recovery"
$e2e = $false

try {
  New-Item -ItemType Directory -Path $work, (Join-Path $work 'tests') -Force | Out-Null
  Get-ChildItem -LiteralPath $candidateRoot -Force | Copy-Item -Destination $work -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'provider_alias.tftest.hcl') -Destination (Join-Path $work 'tests\provider_alias.tftest.hcl')
  Assert-Candidate $work
  Set-Location $work
  Invoke-Terraform @('fmt', '-check', '-recursive') | Out-Null
  Invoke-Terraform @('init', '-input=false', '-no-color') | Out-Null
  Invoke-Terraform @('validate', '-no-color') | Out-Null
  $tests = Invoke-Terraform @('test', '-no-color')
  if (($tests.Output -join "`n") -notmatch '(?m)^Success! 5 passed, 0 failed\.$') { throw 'Exactly 5 canonical runs must pass.' }

  if ($UnitOnly) { Write-Host 'PASS: Terraform 1.6-compatible canonical suite passed 5/5; E2E skipped.'; return }
  if ($null -eq (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI is required.' }
  $health = Invoke-WebRequest -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -UseBasicParsing
  if ($health.StatusCode -ne 200) { throw 'LocalStack is not healthy.' }
  $env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $env:AWS_EC2_METADATA_DISABLED = 'true'
  $e2e = $true

  Invoke-Terraform (@('plan', '-input=false', '-no-color', '-out=initial.tfplan') + $variables) | Out-Null
  Assert-Plan (Read-Plan 'initial.tfplan') $addresses 'create'
  Invoke-Terraform @('apply', '-input=false', '-no-color', 'initial.tfplan') | Out-Null
  $primaryLocation = Invoke-Aws @('--endpoint-url', $LocalstackEndpoint, 's3api', 'get-bucket-location', '--bucket', $primaryBucket, '--query', 'LocationConstraint', '--output', 'text')
  $recoveryLocation = Invoke-Aws @('--endpoint-url', $LocalstackEndpoint, 's3api', 'get-bucket-location', '--bucket', $recoveryBucket, '--query', 'LocationConstraint', '--output', 'text')
  if ($primaryLocation -notin @('None', 'null', '')) { throw "Primary bucket has wrong location: $primaryLocation" }
  if ($recoveryLocation -ne 'us-west-2') { throw "Recovery bucket has wrong location: $recoveryLocation" }
  $clean = Invoke-Terraform (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $variables) @(0)
  if ($clean.ExitCode -ne 0) { throw 'Post-apply plan is not clean.' }

  Invoke-Terraform (@('plan', '-destroy', '-input=false', '-no-color', '-out=destroy.tfplan') + $variables) | Out-Null
  Assert-Plan (Read-Plan 'destroy.tfplan') $addresses 'delete'
  Invoke-Terraform @('apply', '-input=false', '-no-color', 'destroy.tfplan') | Out-Null
  foreach ($bucket in @($primaryBucket, $recoveryBucket)) {
    $old = $ErrorActionPreference
    try { $ErrorActionPreference = 'Continue'; & aws --endpoint-url $LocalstackEndpoint s3api head-bucket --bucket $bucket 2>&1 | Out-Null; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    if ($code -eq 0) { throw "Bucket remains after destroy: $bucket" }
  }
}
finally {
  try {
    if ($e2e -and (Test-Path $work)) { Set-Location $work; Invoke-Terraform (@('destroy', '-auto-approve', '-input=false', '-no-color') + $variables) @(0, 1) | Out-Null }
  } finally { Set-Location $original; if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue } }
}

Write-Host 'PASS: 5/5 canonical runs; provider-slot locations, saved-plan apply, clean plan, audited destroy, and zero residue verified.'
