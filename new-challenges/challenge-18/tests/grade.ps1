[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot '..\starter'),
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Assert-Endpoint([string]$Endpoint) {
  $uri = $null
  $match = [regex]::Match($Endpoint, '\Ahttp://(?:localhost|127\.0\.0\.1):(?<port>[1-9][0-9]{0,4})\z')
  if ([string]::IsNullOrEmpty($Endpoint) -or $Endpoint.IndexOf([char]13) -ge 0 -or $Endpoint.IndexOf([char]10) -ge 0 -or
      -not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or
      -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or $uri.DnsSafeHost -notin @('localhost', '127.0.0.1') -or
      $uri.PathAndQuery -ne '/' -or -not [string]::IsNullOrEmpty($uri.UserInfo)) {
    throw 'LocalstackEndpoint must be a loopback HTTP root origin with a port from 1 to 65535.'
  }
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  $old = $ErrorActionPreference
  try { $ErrorActionPreference = 'Continue'; $text = @(& $File @Arguments 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE }
  finally { $ErrorActionPreference = $old }
  if ($code -notin $Allowed) { throw "$File $($Arguments -join ' ') exited $code.`n$($text -join [Environment]::NewLine)" }
  return [pscustomobject]@{ ExitCode = $code; Text = ($text -join [Environment]::NewLine) }
}

function Invoke-Aws([string[]]$Arguments, [int[]]$Allowed = @(0)) {
  return Invoke-Native 'aws' (@('--endpoint-url', $LocalstackEndpoint) + $Arguments) $Allowed
}

function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if ($item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') -or $item.Extension -eq '.tfplan') { continue }
    if ($item.PSIsContainer) { Copy-Clean $item.FullName (Join-Path $Destination $item.Name) }
    else { Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Destination $item.Name) -Force }
  }
}

function Write-Backend([string]$Path, [string]$Bucket, [string]$Key) {
  $content = @"
bucket = "$Bucket"
key = "$Key"
region = "us-east-1"
access_key = "test"
secret_key = "test"
use_path_style = true
skip_credentials_validation = true
skip_metadata_api_check = true
skip_requesting_account_id = true
endpoints = { s3 = "$LocalstackEndpoint" }
"@
  [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($false))
}

function Read-Plan([string]$Root, [string]$Path) {
  $text = (Invoke-Native 'terraform' @("-chdir=$Root", 'show', '-json', $Path)).Text
  $start = $text.IndexOf('{"format_version"', [StringComparison]::Ordinal)
  if ($start -lt 0) { throw "terraform show did not return JSON for $Path." }
  return ($text.Substring($start) | ConvertFrom-Json)
}

function Assert-Plan([object]$Plan, [string[]]$Expected, [string]$Action, [string]$Label) {
  $changes = @($Plan.resource_changes | Where-Object { (@($_.change.actions) -join ',') -ne 'no-op' })
  $actual = @($changes | ForEach-Object { $_.address } | Sort-Object)
  $wanted = @($Expected | Sort-Object)
  if (($actual -join '|') -cne ($wanted -join '|')) { throw "$Label addresses differ: $($actual -join ', ')." }
  foreach ($change in $changes) {
    if ((@($change.change.actions) -join ',') -cne $Action -or $change.type -notin @('aws_s3_bucket', 'aws_s3_object')) { throw "$Label action/type differs at $($change.address)." }
  }
}

function Assert-Candidate([string]$Root) {
  if (@(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1').Count -ne 0) { throw 'Candidate scripts are out of scope.' }
  foreach ($name in @('foundation', 'workload')) {
    $dir = Join-Path $Root $name
    if (-not (Test-Path $dir -PathType Container)) { throw "Missing $name root." }
    $files = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.tf')
    if ($files.Count -ne 9) { throw "$name must contain the exact five root plus four child-module HCL files." }
    $text = ($files | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
    if ($text -match '(?i)TODO|mock_provider|override_|terraform_data|resource\s+"aws_(vpc|subnet|security_group)"') { throw "$name contains unfinished or out-of-scope configuration." }
    if ([regex]::Matches($text, 'required_version\s*=\s*"~>\s*1\.6"').Count -ne 2 -or [regex]::Matches($text, 'version\s*=\s*"~>\s*5\.100\.0"').Count -ne 2) { throw "$name version contracts differ." }
    if ($text -notmatch 'backend\s+"s3"\s*\{\s*\}') { throw "$name must use a partial S3 backend." }
  }
  $all = (Get-ChildItem $Root -Recurse -File -Filter '*.tf' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  $providerCounts = @{
    'access_key\s*=\s*"test"'                  = 5
    'secret_key\s*=\s*"test"'                  = 5
    's3_use_path_style\s*=\s*true'               = 4
    's3\s*=\s*var\.localstack_endpoint'          = 5
    'sts\s*=\s*var\.localstack_endpoint'         = 4
    'skip_credentials_validation\s*=\s*true'      = 5
    'skip_metadata_api_check\s*=\s*true'          = 5
    'skip_requesting_account_id\s*=\s*true'       = 5
  }
  foreach ($pattern in $providerCounts.Keys) {
    if ([regex]::Matches($all, $pattern).Count -ne $providerCounts[$pattern]) { throw "Provider/remote-state contract mismatch: $pattern" }
  }
  $foundation = (Get-ChildItem (Join-Path $Root 'foundation') -Recurse -File -Filter '*.tf' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  $workload = (Get-ChildItem (Join-Path $Root 'workload') -Recurse -File -Filter '*.tf' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  if ([regex]::Matches($foundation, 'resource\s+"aws_s3_bucket"\s+"this"').Count -ne 1 -or [regex]::Matches($foundation, 'data\s+"aws_caller_identity"').Count -ne 1) { throw 'Foundation module resource/data contract differs.' }
  if ([regex]::Matches($workload, 'resource\s+"aws_s3_object"\s+"service"').Count -ne 1 -or $workload -notmatch 'data\s+"terraform_remote_state"\s+"foundation"') { throw 'Workload module/remote-state contract differs.' }
  if ($foundation -notmatch 'aws\s*=\s*aws\.primary' -or $foundation -notmatch 'aws\s*=\s*aws\.dr' -or
      $workload -notmatch 'aws\s*=\s*aws\.primary' -or $workload -notmatch 'aws\s*=\s*aws\.dr') { throw 'Static provider mappings are incomplete.' }
  foreach ($pattern in @('endpoints\s*=\s*\{\s*s3\s*=\s*var\.localstack_endpoint', 'use_path_style\s*=\s*true', 'backend\s*=\s*"s3"')) {
    if ($workload -notmatch $pattern) { throw "Remote-state contract missing: $pattern" }
  }
}

Assert-Endpoint $LocalstackEndpoint
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw 'terraform is required.' }
if ($null -eq (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI is required.' }
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
Assert-Candidate $candidateRoot
$lab = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$foundationTests = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'foundation.tftest.hcl') -Raw
$workloadTests = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'workload.tftest.hcl') -Raw
if (($foundationTests + $workloadTests) -match 'mock_provider|override_' -or ([regex]::Matches(($foundationTests + $workloadTests), '(?m)^run\s+"')).Count -ne 9) { throw 'Canonical suite must contain exactly nine Terraform 1.6 runs.' }

$health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get
foreach ($service in @('s3', 'sts')) { if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." } }
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED')) { $envBefore[$name] = [Environment]::GetEnvironmentVariable($name) }
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $env:AWS_EC2_METADATA_DISABLED = 'true'

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 10)
$prefix = "c18-$suffix"
$stateBucket = "tfpro-c18-state-$suffix"
$foundationKey = 'foundation/terraform.tfstate'
$workloadKey = 'workload/terraform.tfstate'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c18-' + [guid]::NewGuid().ToString('N'))
$candidateWork = Join-Path $scratch 'candidate'
$fixtures = Join-Path $scratch 'fixtures'
$foundation = Join-Path $candidateWork 'foundation'
$workload = Join-Path $candidateWork 'workload'
$foundationBackend = Join-Path $scratch 'foundation.backend.hcl'
$workloadBackend = Join-Path $scratch 'workload.backend.hcl'
$foundationBase = @('-input=false', "-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint")
$workloadBase = @('-input=false', "-var=state_bucket=$stateBucket", "-var=foundation_state_key=$foundationKey", "-var=localstack_endpoint=$LocalstackEndpoint")
$foundationAddresses = @('module.dr.aws_s3_bucket.this', 'module.primary.aws_s3_bucket.this')
$workloadAddresses = @(
  'module.service_primary["api@primary"].aws_s3_object.service',
  'module.service_primary["metrics@primary"].aws_s3_object.service',
  'module.service_dr["metrics@dr"].aws_s3_object.service',
  'module.service_dr["worker@dr"].aws_s3_object.service'
)
$stateCreated = $false
$foundationApplied = $false
$workloadApplied = $false

try {
  Copy-Clean $candidateRoot $candidateWork
  Copy-Clean (Join-Path $lab 'fixtures') $fixtures
  New-Item -ItemType Directory -Path (Join-Path $foundation 'tests'), (Join-Path $workload 'tests') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'foundation.tftest.hcl') -Destination (Join-Path $foundation 'tests\foundation.tftest.hcl')
  $renderedWorkloadTests = $workloadTests.Replace('__STATE_BUCKET__', $stateBucket).Replace('__FOUNDATION_KEY__', $foundationKey)
  [IO.File]::WriteAllText((Join-Path $workload 'tests\workload.tftest.hcl'), $renderedWorkloadTests, [Text.UTF8Encoding]::new($false))
  Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $candidateWork) | Out-Null
  Invoke-Aws @('s3api', 'create-bucket', '--bucket', $stateBucket) | Out-Null
  $stateCreated = $true
  Write-Backend $foundationBackend $stateBucket $foundationKey
  Write-Backend $workloadBackend $stateBucket $workloadKey

  Invoke-Native 'terraform' @("-chdir=$foundation", 'init', '-input=false', "-backend-config=$foundationBackend") | Out-Null
  Invoke-Native 'terraform' @("-chdir=$foundation", 'validate', '-no-color') | Out-Null
  $foundationPlan = Join-Path $scratch 'foundation.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$foundation", 'plan', "-out=$foundationPlan") + $foundationBase) | Out-Null
  Assert-Plan (Read-Plan $foundation $foundationPlan) $foundationAddresses 'create' 'Foundation saved plan'
  Invoke-Native 'terraform' @("-chdir=$foundation", 'apply', '-input=false', $foundationPlan) | Out-Null
  $foundationApplied = $true
  $foundationTestResult = Invoke-Native 'terraform' @("-chdir=$foundation", 'test', '-no-color')
  if ($foundationTestResult.Text -notmatch 'Success! 4 passed, 0 failed') { throw 'Foundation canonical run count/result mismatch.' }

  Invoke-Native 'terraform' @("-chdir=$workload", 'init', '-input=false', "-backend-config=$workloadBackend") | Out-Null
  Invoke-Native 'terraform' @("-chdir=$workload", 'validate', '-no-color') | Out-Null
  $workloadTestResult = Invoke-Native 'terraform' @("-chdir=$workload", 'test', '-no-color')
  if ($workloadTestResult.Text -notmatch 'Success! 5 passed, 0 failed') { throw 'Workload canonical run count/result mismatch.' }
  Write-Host '[unit] both roots fmt/init/validate; 9 Terraform 1.6 normal plan runs passed on real S3 state.'

  if ($UnitOnly) {
    Invoke-Native 'terraform' (@("-chdir=$foundation", 'destroy', '-auto-approve') + $foundationBase) | Out-Null
    $foundationApplied = $false
    Invoke-Aws @('s3', 'rm', "s3://$stateBucket", '--recursive') | Out-Null
    Invoke-Aws @('s3api', 'delete-bucket', '--bucket', $stateBucket) | Out-Null
    $stateCreated = $false
    Write-Host 'PASS challenge-18 UnitOnly'
    return
  }

  $primaryLocation = (Invoke-Aws @('s3api', 'get-bucket-location', '--bucket', "$prefix-primary", '--query', 'LocationConstraint', '--output', 'text')).Text.Trim()
  $drLocation = (Invoke-Aws @('s3api', 'get-bucket-location', '--bucket', "$prefix-dr", '--query', 'LocationConstraint', '--output', 'text')).Text.Trim()
  if ($primaryLocation -notin @('', 'None', 'null') -or $drLocation -cne 'us-west-2') { throw 'Provider aliases did not create buckets in their expected regions.' }

  $workloadPlan = Join-Path $scratch 'workload.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$workload", 'plan', "-out=$workloadPlan") + $workloadBase) | Out-Null
  Assert-Plan (Read-Plan $workload $workloadPlan) $workloadAddresses 'create' 'Workload saved plan'
  Invoke-Native 'terraform' @("-chdir=$workload", 'apply', '-input=false', $workloadPlan) | Out-Null
  $workloadApplied = $true

  $foundationState = @((Invoke-Native 'terraform' @("-chdir=$foundation", 'state', 'list')).Text -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '\.data\.' })
  $workloadState = @((Invoke-Native 'terraform' @("-chdir=$workload", 'state', 'list')).Text -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '^data\.' })
  $foundationActual = (@($foundationState | Sort-Object) -join '|')
  $foundationExpected = (@($foundationAddresses | Sort-Object) -join '|')
  $workloadActual = (@($workloadState | Sort-Object) -join '|')
  $workloadExpected = (@($workloadAddresses | Sort-Object) -join '|')
  if ($foundationActual -cne $foundationExpected -or $workloadActual -cne $workloadExpected) { throw 'State ownership/address contracts differ.' }

  $apiFile = Join-Path $scratch 'api.json'
  Invoke-Aws @('s3api', 'get-object', '--bucket', "$prefix-primary", '--key', 'services/prod/api.json', $apiFile) | Out-Null
  $api = Get-Content $apiFile -Raw | ConvertFrom-Json
  if ($api.name -cne 'api' -or $api.owner -cne 'platform' -or $api.port -ne 443) { throw 'Primary API object content differs.' }
  foreach ($bucket in @("$prefix-primary", "$prefix-dr")) { Invoke-Aws @('s3api', 'head-object', '--bucket', $bucket, '--key', 'services/prod/metrics.json') | Out-Null }

  $reordered = Invoke-Native 'terraform' (@("-chdir=$workload", 'plan', '-detailed-exitcode') + $workloadBase + @("-var=catalog_file=$(Join-Path $fixtures 'services-reordered.csv')")) @(0, 2)
  if ($reordered.ExitCode -ne 0) { throw 'Reordered CSV must produce a clean workload plan.' }

  [IO.File]::WriteAllText($apiFile, '{"name":"api","owner":"manual","tier":"critical","port":1}', [Text.UTF8Encoding]::new($false))
  Invoke-Aws @('s3api', 'put-object', '--bucket', "$prefix-primary", '--key', 'services/prod/api.json', '--body', $apiFile, '--content-type', 'application/json') | Out-Null
  $repair = Join-Path $scratch 'repair.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$workload", 'plan', "-out=$repair") + $workloadBase) | Out-Null
  Assert-Plan (Read-Plan $workload $repair) @('module.service_primary["api@primary"].aws_s3_object.service') 'update' 'Workload repair plan'
  Invoke-Native 'terraform' @("-chdir=$workload", 'apply', '-input=false', $repair) | Out-Null
  Invoke-Aws @('s3api', 'get-object', '--bucket', "$prefix-primary", '--key', 'services/prod/api.json', $apiFile) | Out-Null
  if ((Get-Content $apiFile -Raw | ConvertFrom-Json).owner -cne 'platform') { throw 'Workload repair did not restore API content.' }

  $foundationClean = Invoke-Native 'terraform' (@("-chdir=$foundation", 'plan', '-detailed-exitcode') + $foundationBase) @(0, 2)
  $workloadClean = Invoke-Native 'terraform' (@("-chdir=$workload", 'plan', '-detailed-exitcode') + $workloadBase) @(0, 2)
  if ($foundationClean.ExitCode -ne 0 -or $workloadClean.ExitCode -ne 0) { throw 'Final root plans are not clean.' }

  $workloadDestroy = Join-Path $scratch 'workload-destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$workload", 'plan', '-destroy', "-out=$workloadDestroy") + $workloadBase) | Out-Null
  Assert-Plan (Read-Plan $workload $workloadDestroy) $workloadAddresses 'delete' 'Workload destroy plan'
  Invoke-Native 'terraform' @("-chdir=$workload", 'apply', '-input=false', $workloadDestroy) | Out-Null
  $workloadApplied = $false

  $foundationDestroy = Join-Path $scratch 'foundation-destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$foundation", 'plan', '-destroy', "-out=$foundationDestroy") + $foundationBase) | Out-Null
  Assert-Plan (Read-Plan $foundation $foundationDestroy) $foundationAddresses 'delete' 'Foundation destroy plan'
  Invoke-Native 'terraform' @("-chdir=$foundation", 'apply', '-input=false', $foundationDestroy) | Out-Null
  $foundationApplied = $false

  Invoke-Aws @('s3', 'rm', "s3://$stateBucket", '--recursive') | Out-Null
  Invoke-Aws @('s3api', 'delete-bucket', '--bucket', $stateBucket) | Out-Null
  $stateCreated = $false
  $remaining = (Invoke-Aws @('s3api', 'list-buckets', '--query', "Buckets[?starts_with(Name, '$prefix') || Name=='$stateBucket'].Name", '--output', 'text')).Text.Trim()
  if ($remaining) { throw "S3 residue remains: $remaining" }
  Write-Host 'PASS challenge-18: 9/9 tests, dual-region routing, S3 remote state, drift repair, reverse saved destroy, zero residue.'
}
finally {
  if ($workloadApplied -and (Test-Path $workload)) { try { Invoke-Native 'terraform' (@("-chdir=$workload", 'destroy', '-auto-approve') + $workloadBase) @(0, 1) | Out-Null } catch {} }
  if ($foundationApplied -and (Test-Path $foundation)) { try { Invoke-Native 'terraform' (@("-chdir=$foundation", 'destroy', '-auto-approve') + $foundationBase) @(0, 1) | Out-Null } catch {} }
  if ($stateCreated) { try { Invoke-Aws @('s3', 'rm', "s3://$stateBucket", '--recursive') @(0, 1, 255) | Out-Null; Invoke-Aws @('s3api', 'delete-bucket', '--bucket', $stateBucket) @(0, 255) | Out-Null } catch {} }
  foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
  if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
