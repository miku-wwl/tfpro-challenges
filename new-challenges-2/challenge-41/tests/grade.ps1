param(
  [string]$Candidate = '',
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)
if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }
$ErrorActionPreference = 'Stop'

function Assert-Endpoint([string]$Endpoint) {
  if ([string]::IsNullOrWhiteSpace($Endpoint) -or $Endpoint.Contains("`r") -or $Endpoint.Contains("`n")) {
    throw 'LocalstackEndpoint must be a single-line loopback HTTP root origin.'
  }
  $match = [regex]::Match($Endpoint, '\Ahttp://(?:localhost|127\.0\.0\.1|\[::1\]):(?<port>[1-9][0-9]{0,4})\z')
  $uri = $null
  if (-not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or
      -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
      -not [string]::IsNullOrEmpty($uri.UserInfo) -or $uri.PathAndQuery -ne '/') {
    throw 'LocalstackEndpoint must be an explicit loopback HTTP root origin with a valid port.'
  }
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  $oldPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $lines = @(& $File @Arguments 2>&1)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $oldPreference
  $value = $lines -join [Environment]::NewLine
  if ($code -notin $Allowed) { throw "$File $($Arguments -join ' ') exited $code.`n$value" }
  return @{ ExitCode = $code; Text = $value }
}

function Invoke-Aws([string[]]$Arguments, [int[]]$Allowed = @(0)) {
  return Invoke-Native 'aws' (@('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1') + $Arguments) $Allowed
}

function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if ($item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') -or $item.Extension -eq '.tfplan') { continue }
    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Destination $item.Name) -Recurse -Force
  }
}

function Read-Plan([string]$Root, [string]$Path) {
  $text = (Invoke-Native 'terraform' @("-chdir=$Root", 'show', '-json', $Path)).Text
  $start = $text.IndexOf('{"format_version"', [StringComparison]::Ordinal)
  if ($start -lt 0) { throw "terraform show did not return plan JSON for $Path." }
  return ($text.Substring($start) | ConvertFrom-Json)
}

function Action-Map([object]$Plan) {
  $map = @{}
  foreach ($change in @($Plan.resource_changes | Where-Object { $_.mode -eq 'managed' })) {
    $action = @($change.change.actions) -join ','
    if ($action -ne 'no-op' -and $action -ne 'read') { $map[$change.address] = $action }
  }
  return $map
}

function Assert-Actions([hashtable]$Actual, [hashtable]$Expected, [string]$Label) {
  if ($Actual.Count -ne $Expected.Count) { throw "$Label action count differs: actual=$($Actual.Count), expected=$($Expected.Count)." }
  foreach ($address in $Expected.Keys) {
    if (-not $Actual.ContainsKey($address) -or $Actual[$address] -ne $Expected[$address]) {
      throw "$Label action differs at ${address}: $($Actual[$address])."
    }
  }
}

function Assert-Candidate([string]$Root) {
  $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.tf')
  if ($files.Count -eq 0 -or @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1').Count -ne 0) { throw 'Candidate must contain Terraform HCL only.' }
  $text = ($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
  if ($text -match '(?i)\bTODO\b|mock_provider|override_|terraform_data|aws_sns|aws_vpc|aws_subnet|terraform\s+state\s+mv') { throw 'Candidate is unfinished or contains a prohibited construct.' }
  if ([regex]::Matches($text, '(?m)^\s*moved\s*\{').Count -ne 6) { throw 'Exactly six moved blocks are required.' }
  if ($text -match '(?m)^\s*count\s*=') { throw 'Candidate managed resources must not use count.' }
  $resources = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if (($resources -join '|') -cne 'aws_iam_role|aws_s3_bucket|aws_s3_object') { throw "Managed AWS type set differs: $($resources -join ',')." }
  $data = @([regex]::Matches($text, 'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if (($data -join '|') -cne 'aws_iam_policy_document') { throw "AWS data source set differs: $($data -join ',')." }
  foreach ($pattern in @('required_version\s*=\s*"~>\s*1\.6"', 'version\s*=\s*"~>\s*5\.100"', 'access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"', 'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true', 'skip_requesting_account_id\s*=\s*true', '(?m)^\s*iam\s*=\s*var\.localstack_endpoint\s*$', '(?m)^\s*s3\s*=\s*var\.localstack_endpoint\s*$', '(?m)^\s*sts\s*=\s*var\.localstack_endpoint\s*$')) {
    if ($text -notmatch $pattern) { throw "Candidate provider/version contract is missing: $pattern" }
  }
  if ($text -match '(?m)^\s*(ec2|sns|sqs|lambda|dynamodb|kms)\s*=\s*var\.localstack_endpoint') { throw 'Candidate provider has an out-of-scope endpoint.' }
  foreach ($source in @('aws_s3_bucket.release[0]', 'aws_s3_object.manifest[0]', 'aws_iam_role.publisher[0]', 'aws_s3_bucket.release[1]', 'aws_s3_object.manifest[1]', 'aws_iam_role.publisher[1]')) {
    if ($text -notmatch [regex]::Escape($source)) { throw "Moved source is missing: $source" }
  }
}

Assert-Endpoint $LocalstackEndpoint
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw 'terraform is required.' }
if ($null -eq (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI is required.' }
$terraformVersion = (& terraform version -json | ConvertFrom-Json).terraform_version
if ($LASTEXITCODE -ne 0 -or $terraformVersion -ne '1.6.6') { throw "Terraform 1.6.6 is required; active version is $terraformVersion." }
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
Assert-Candidate $candidateRoot
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$canonical = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Raw
if ($canonical -match '(?i)mock_provider|override_' -or [regex]::Matches($canonical, '(?m)^\s*run\s+"').Count -ne 7) { throw 'Canonical suite must contain exactly seven normal Terraform 1.6 runs.' }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c41-' + [guid]::NewGuid().ToString('N'))
$candidateWork = Join-Path $tempRoot 'candidate'
$fixturesWork = Join-Path $tempRoot 'fixtures'
$legacyWork = Join-Path $fixturesWork 'legacy'
$runId = 'c41-' + [guid]::NewGuid().ToString('N').Substring(0, 10)
$vars = @("-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
$expectedCurrent = @(
  'module.service["api"].aws_iam_role.publisher',
  'module.service["api"].aws_s3_bucket.release',
  'module.service["api"].aws_s3_object.manifest',
  'module.service["worker"].aws_iam_role.publisher',
  'module.service["worker"].aws_s3_bucket.release',
  'module.service["worker"].aws_s3_object.manifest'
)
$previous = @{
  'module.service["api"].aws_iam_role.publisher'       = 'aws_iam_role.publisher[0]'
  'module.service["api"].aws_s3_bucket.release'       = 'aws_s3_bucket.release[0]'
  'module.service["api"].aws_s3_object.manifest'      = 'aws_s3_object.manifest[0]'
  'module.service["worker"].aws_iam_role.publisher'   = 'aws_iam_role.publisher[1]'
  'module.service["worker"].aws_s3_bucket.release'    = 'aws_s3_bucket.release[1]'
  'module.service["worker"].aws_s3_object.manifest'   = 'aws_s3_object.manifest[1]'
}
$candidateOwns = $false
$applied = $false
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED')) { $envBefore[$name] = [Environment]::GetEnvironmentVariable($name) }
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $env:AWS_EC2_METADATA_DISABLED = 'true'

try {
  Copy-Clean $candidateRoot $candidateWork
  Copy-Clean (Join-Path $labRoot 'fixtures') $fixturesWork
  New-Item -ItemType Directory -Path (Join-Path $candidateWork 'tests') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $candidateWork 'tests\canonical.tftest.hcl') -Force
  Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $candidateWork) | Out-Null
  Invoke-Native 'terraform' @("-chdir=$candidateWork", 'init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Invoke-Native 'terraform' @("-chdir=$candidateWork", 'validate', '-no-color') | Out-Null
  $tests = Invoke-Native 'terraform' @("-chdir=$candidateWork", 'test', '-no-color')
  if ($tests.Text -notmatch 'Success! 7 passed, 0 failed') { throw 'Canonical test result/count differs.' }
  Write-Host '[unit] 7/7 Terraform 1.6 normal plan runs passed.'
  if ($UnitOnly) { Write-Host 'PASS challenge-41 UnitOnly'; return }

  $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get
  foreach ($service in @('iam', 's3', 'sts')) { if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." } }

  Invoke-Native 'terraform' @("-chdir=$legacyWork", 'init', '-backend=false', '-input=false', '-no-color') | Out-Null
  $legacyPlan = Join-Path $tempRoot 'legacy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$legacyWork", 'plan', '-input=false', '-no-color', "-out=$legacyPlan") + $vars) | Out-Null
  $legacyExpected = @{}
  foreach ($address in @('aws_iam_role.publisher[0]', 'aws_iam_role.publisher[1]', 'aws_s3_bucket.release[0]', 'aws_s3_bucket.release[1]', 'aws_s3_object.manifest[0]', 'aws_s3_object.manifest[1]')) { $legacyExpected[$address] = 'create' }
  Assert-Actions (Action-Map (Read-Plan $legacyWork $legacyPlan)) $legacyExpected 'Legacy plan'
  Invoke-Native 'terraform' @("-chdir=$legacyWork", 'apply', '-input=false', '-no-color', $legacyPlan) | Out-Null
  $applied = $true
  Copy-Item -LiteralPath (Join-Path $legacyWork 'terraform.tfstate') -Destination (Join-Path $candidateWork 'terraform.tfstate') -Force
  $candidateOwns = $true

  $migrationPlan = Join-Path $tempRoot 'migration.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$candidateWork", 'plan', '-input=false', '-no-color', "-out=$migrationPlan") + $vars) | Out-Null
  $migration = Read-Plan $candidateWork $migrationPlan
  Assert-Actions (Action-Map $migration) @{} 'Migration plan'
  $managed = @($migration.resource_changes | Where-Object { $_.mode -eq 'managed' })
  if ($managed.Count -ne 6) { throw "Migration must contain six managed no-op changes, found $($managed.Count)." }
  foreach ($change in $managed) {
    if (-not $previous.ContainsKey($change.address) -or $change.previous_address -ne $previous[$change.address] -or (@($change.change.actions) -join ',') -ne 'no-op') {
      throw "Migration move metadata differs at $($change.address)."
    }
  }
  Invoke-Native 'terraform' @("-chdir=$candidateWork", 'apply', '-input=false', '-no-color', $migrationPlan) | Out-Null

  $managedState = @((Invoke-Native 'terraform' @("-chdir=$candidateWork", 'state', 'list')).Text -split "`r?`n" | Where-Object { $_ -match '\.aws_(iam_role|s3_bucket|s3_object)\.' } | Sort-Object)
  if (($managedState -join '|') -cne (($expectedCurrent | Sort-Object) -join '|')) { throw "Migrated managed state addresses differ: $($managedState -join ', ')." }
  $clean = Invoke-Native 'terraform' (@("-chdir=$candidateWork", 'plan', '-detailed-exitcode', '-input=false', '-no-color') + $vars) @(0, 2)
  if ($clean.ExitCode -ne 0) { throw 'Post-migration plan is not clean.' }
  $reorder = Invoke-Native 'terraform' (@("-chdir=$candidateWork", 'plan', '-detailed-exitcode', '-input=false', '-no-color') + $vars + @('-var=catalog_path=../fixtures/services-reordered.json')) @(0, 2)
  if ($reorder.ExitCode -ne 0) { throw 'Reordered catalog changed the graph.' }

  $driftBody = Join-Path $tempRoot 'drift.json'
  [IO.File]::WriteAllText($driftBody, '{"drift":true}', [Text.UTF8Encoding]::new($false))
  Invoke-Aws @('s3api', 'put-object', '--bucket', "$runId-api-release", '--key', 'release/manifest.json', '--body', $driftBody) | Out-Null
  $repairPlan = Join-Path $tempRoot 'repair.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$candidateWork", 'plan', '-input=false', '-no-color', "-out=$repairPlan") + $vars) | Out-Null
  Assert-Actions (Action-Map (Read-Plan $candidateWork $repairPlan)) @{ 'module.service["api"].aws_s3_object.manifest' = 'update' } 'Drift repair'
  Invoke-Native 'terraform' @("-chdir=$candidateWork", 'apply', '-input=false', '-no-color', $repairPlan) | Out-Null

  $destroyPlan = Join-Path $tempRoot 'destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$candidateWork", 'plan', '-destroy', '-input=false', '-no-color', "-out=$destroyPlan") + $vars) | Out-Null
  $destroyExpected = @{}; foreach ($address in $expectedCurrent) { $destroyExpected[$address] = 'delete' }
  Assert-Actions (Action-Map (Read-Plan $candidateWork $destroyPlan)) $destroyExpected 'Destroy plan'
  Invoke-Native 'terraform' @("-chdir=$candidateWork", 'apply', '-input=false', '-no-color', $destroyPlan) | Out-Null
  $applied = $false

  $buckets = (Invoke-Aws @('s3api', 'list-buckets', '--output', 'json')).Text | ConvertFrom-Json
  if (@($buckets.Buckets | Where-Object { $_.Name -like "$runId-*" }).Count -ne 0) { throw 'S3 residue remains.' }
  $roles = (Invoke-Aws @('iam', 'list-roles', '--output', 'json')).Text | ConvertFrom-Json
  if (@($roles.Roles | Where-Object { $_.RoleName -like "$runId-*" }).Count -ne 0) { throw 'IAM residue remains.' }
  $remainingState = @((Invoke-Native 'terraform' @("-chdir=$candidateWork", 'state', 'list')).Text -split "`r?`n" | Where-Object { $_ -match '\.aws_(iam_role|s3_bucket|s3_object)\.' })
  if ($remainingState.Count -ne 0) { throw 'Managed state residue remains.' }
  Write-Host 'PASS challenge-41: 7/7 tests, six no-op moves, reorder, object drift repair, saved destroy, zero residue.'
}
finally {
  if ($applied) {
    $cleanupRoot = if ($candidateOwns) { $candidateWork } else { $legacyWork }
    if (Test-Path $cleanupRoot) { try { Invoke-Native 'terraform' (@("-chdir=$cleanupRoot", 'destroy', '-auto-approve', '-input=false', '-no-color') + $vars) @(0, 1) | Out-Null } catch {} }
  }
  foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
