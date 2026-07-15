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
  $files = @(Get-ChildItem -LiteralPath $Root -File -Filter '*.tf')
  if ($files.Count -ne 5) { throw 'Candidate must contain exactly five root Terraform files.' }
  if (@(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1').Count -ne 0) { throw 'Candidate scripts are out of scope.' }
  $text = ($files | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  if ($text -match '(?i)TODO|mock_provider|override_|state\s+(push|rm)|ignore_changes') { throw 'Candidate is unfinished or uses a forbidden workaround.' }
  if ($text -notmatch 'required_version\s*=\s*"~>\s*1\.6"' -or $text -notmatch 'version\s*=\s*"~>\s*5\.100\.0"') { throw 'Version constraints differ.' }
  foreach ($pattern in @('access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"', 's3_use_path_style\s*=\s*true', 's3\s*=\s*var\.localstack_endpoint', 'sts\s*=\s*var\.localstack_endpoint', 'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true', 'skip_requesting_account_id\s*=\s*true')) {
    if ($text -notmatch $pattern) { throw "Provider contract missing: $pattern" }
  }
  $resources = @([regex]::Matches($text, 'resource\s+"([^"]+)"\s+"([^"]+)"') | ForEach-Object { "$($_.Groups[1].Value).$($_.Groups[2].Value)" } | Sort-Object)
  if (($resources -join '|') -cne 'aws_s3_bucket.inventory|aws_s3_object.index|aws_s3_object.service') { throw 'Managed resource block set is not exact.' }
  $checks = @([regex]::Matches($text, 'check\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  if (($checks -join '|') -cne 'catalog_not_empty|enabled_services_present|service_fields_valid|service_names_unique') { throw 'Check contract is not exact.' }
  foreach ($pattern in @('for_each\s*=\s*local\.services', 'etag\s*=\s*md5\(', 'metadata\s*=', 'tags\s*=', 'sha256\(jsonencode\(local\.canonical_inventory\)\)')) {
    if ($text -notmatch $pattern) { throw "Inventory contract missing: $pattern" }
  }
}

Assert-Endpoint $LocalstackEndpoint
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw 'terraform is required.' }
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
Assert-Candidate $candidateRoot
$lab = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testSource = Join-Path $PSScriptRoot 'inventory.tftest.hcl'
$testText = Get-Content -LiteralPath $testSource -Raw
if ($testText -match 'mock_provider|override_' -or [regex]::Matches($testText, '(?m)^run\s+"').Count -ne 7) { throw 'Canonical suite must contain exactly seven Terraform 1.6 runs.' }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c16-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $scratch 'candidate'
$fixtures = Join-Path $scratch 'fixtures'
$prefix = 'c16-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$bucket = "$prefix-prod-inventory"
$canonical = Join-Path $fixtures 'services.json'
$reordered = Join-Path $fixtures 'services-reordered.json'
$base = @("-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=catalog_file=$canonical")
$addresses = @('aws_s3_bucket.inventory', 'aws_s3_object.index', 'aws_s3_object.service["api"]', 'aws_s3_object.service["worker"]')
$applied = $false
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED')) { $envBefore[$name] = [Environment]::GetEnvironmentVariable($name) }

try {
  New-Item -ItemType Directory -Path $work, $fixtures, (Join-Path $work 'tests') -Force | Out-Null
  Get-ChildItem -LiteralPath $candidateRoot -Force | Copy-Item -Destination $work -Recurse -Force
  Get-ChildItem -LiteralPath (Join-Path $lab 'fixtures') -Force | Copy-Item -Destination $fixtures -Recurse -Force
  Copy-Item -LiteralPath $testSource -Destination (Join-Path $work 'tests\inventory.tftest.hcl')
  Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $work) | Out-Null
  Invoke-Native 'terraform' @("-chdir=$work", 'init', '-input=false', '-no-color') | Out-Null
  Invoke-Native 'terraform' @("-chdir=$work", 'validate', '-no-color') | Out-Null
  $tests = Invoke-Native 'terraform' @("-chdir=$work", 'test', '-no-color')
  if ($tests.Text -notmatch 'Success! 7 passed, 0 failed') { throw 'Canonical run count/result mismatch.' }
  Write-Host '[unit] 7 Terraform 1.6 normal plan runs passed.'
  if ($UnitOnly) { Write-Host 'PASS challenge-16 UnitOnly'; return }

  if ($null -eq (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI is required.' }
  $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get
  foreach ($service in @('s3', 'sts')) { if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." } }
  $env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $env:AWS_EC2_METADATA_DISABLED = 'true'

  $initial = Join-Path $scratch 'initial.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-input=false', "-out=$initial") + $base) | Out-Null
  Assert-Plan (Read-Plan $work $initial) $addresses 'create' 'Initial plan'
  $initialHash = (Get-FileHash -LiteralPath $initial -Algorithm SHA256).Hash
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', $initial) | Out-Null
  if ((Get-FileHash -LiteralPath $initial -Algorithm SHA256).Hash -cne $initialHash) { throw 'Saved plan changed during apply.' }
  $applied = $true

  $stateText = (Invoke-Native 'terraform' @("-chdir=$work", 'state', 'pull')).Text
  [IO.File]::WriteAllText((Join-Path $scratch 'state-backup.json'), $stateText, [Text.UTF8Encoding]::new($false))
  $state = $stateText | ConvertFrom-Json
  $instanceCount = @($state.resources | ForEach-Object { @($_.instances) }).Count
  if ($instanceCount -ne 4) { throw 'Read-only state backup does not contain the four managed instances.' }

  $clean = Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-detailed-exitcode', '-input=false') + $base) @(0, 2)
  if ($clean.ExitCode -ne 0) { throw 'Post-apply plan is not clean.' }
  $reorderVars = @("-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=catalog_file=$reordered")
  $reorderPlan = Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-detailed-exitcode', '-input=false') + $reorderVars) @(0, 2)
  if ($reorderPlan.ExitCode -ne 0) { throw 'Reordered input must produce a clean plan.' }

  # Persist provider-computed S3 normalization before injecting the intentional drift,
  # so the following refresh-only evidence isolates only the external mutation.
  $baselineRefresh = Join-Path $scratch 'baseline-refresh.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-refresh-only', '-input=false', "-out=$baselineRefresh") + $base) | Out-Null
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', $baselineRefresh) | Out-Null

  $tampered = Join-Path $scratch 'tampered.json'
  [IO.File]::WriteAllText($tampered, '{"name":"api","owner":"attacker","tier":"critical","enabled":true,"environment":"prod"}', [Text.UTF8Encoding]::new($false))
  Invoke-Aws @('s3api', 'put-object', '--bucket', $bucket, '--key', 'services/api.json', '--body', $tampered, '--content-type', 'application/json') | Out-Null
  Invoke-Aws @('s3api', 'put-object-tagging', '--bucket', $bucket, '--key', 'services/api.json', '--tagging', 'TagSet=[{Key=ManagedBy,Value=manual},{Key=Service,Value=api}]') | Out-Null

  $refresh = Join-Path $scratch 'refresh.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-refresh-only', '-input=false', "-out=$refresh") + $base) | Out-Null
  $refreshJson = Read-Plan $work $refresh
  $drift = @($refreshJson.resource_drift | Where-Object { (@($_.change.actions) -join ',') -ne 'no-op' })
  $driftSummary = @($drift | ForEach-Object { "$($_.address):$(@($_.change.actions) -join ',')" }) -join '; '
  if ($drift.Count -ne 1 -or $drift[0].address -cne 'aws_s3_object.service["api"]') { throw "Refresh-only plan did not isolate the real API object drift: $driftSummary" }
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', $refresh) | Out-Null

  $repair = Join-Path $scratch 'repair.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-input=false', "-out=$repair") + $base) | Out-Null
  Assert-Plan (Read-Plan $work $repair) @('aws_s3_object.service["api"]') 'update' 'Repair plan'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', $repair) | Out-Null
  $restored = Join-Path $scratch 'restored.json'
  Invoke-Aws @('s3api', 'get-object', '--bucket', $bucket, '--key', 'services/api.json', $restored) | Out-Null
  $restoredJson = Get-Content -LiteralPath $restored -Raw | ConvertFrom-Json
  if ($restoredJson.owner -cne 'platform' -or $restoredJson.environment -cne 'prod') { throw 'Repair did not restore declared content.' }
  $postRepair = Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-detailed-exitcode', '-input=false') + $base) @(0, 2)
  if ($postRepair.ExitCode -ne 0) { throw 'Post-repair plan is not clean.' }

  $destroy = Join-Path $scratch 'destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-destroy', '-input=false', "-out=$destroy") + $base) | Out-Null
  Assert-Plan (Read-Plan $work $destroy) $addresses 'delete' 'Destroy plan'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', $destroy) | Out-Null
  $applied = $false
  $remaining = (Invoke-Aws @('s3api', 'list-buckets', '--query', "Buckets[?Name=='$bucket'].Name", '--output', 'text')).Text.Trim()
  if ($remaining) { throw 'Inventory bucket remains after destroy.' }
  Write-Host 'PASS challenge-16: 7/7 tests, immutable saved plan, state pull, refresh-only drift, precise repair, saved destroy, zero residue.'
}
finally {
  if ($applied -and (Test-Path $work)) { try { Invoke-Native 'terraform' (@("-chdir=$work", 'destroy', '-auto-approve', '-input=false') + $base) @(0, 1) | Out-Null } catch {} }
  foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
  if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
