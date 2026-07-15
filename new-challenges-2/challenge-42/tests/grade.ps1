param(
  [string]$Candidate = '',
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)
if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }
$ErrorActionPreference = 'Stop'

function Assert-Endpoint([string]$Endpoint) {
  if ([string]::IsNullOrWhiteSpace($Endpoint) -or $Endpoint.Contains("`r") -or $Endpoint.Contains("`n")) { throw 'LocalstackEndpoint must be a single-line loopback HTTP root origin.' }
  $match = [regex]::Match($Endpoint, '\Ahttp://(?:localhost|127\.0\.0\.1|\[::1\]):(?<port>[1-9][0-9]{0,4})\z')
  $uri = $null
  if (-not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or -not [string]::IsNullOrEmpty($uri.UserInfo) -or $uri.PathAndQuery -ne '/') { throw 'LocalstackEndpoint must be an explicit loopback HTTP root origin with a valid port.' }
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $lines = @(& $File @Arguments 2>&1); $code = $LASTEXITCODE
  $ErrorActionPreference = $old; $value = $lines -join [Environment]::NewLine
  if ($code -notin $Allowed) { throw "$File $($Arguments -join ' ') exited $code.`n$value" }
  return @{ ExitCode = $code; Text = $value }
}

function Invoke-Aws([string]$Region, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  return Invoke-Native 'aws' (@('--endpoint-url', $LocalstackEndpoint, '--region', $Region) + $Arguments) $Allowed
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
    if (-not $Actual.ContainsKey($address) -or $Actual[$address] -ne $Expected[$address]) { throw "$Label action differs at ${address}: $($Actual[$address])." }
  }
}

function Assert-Candidate([string]$Root) {
  $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.tf')
  if ($files.Count -eq 0 -or @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1').Count -ne 0) { throw 'Candidate must contain Terraform HCL only.' }
  $text = ($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
  if ($text -match '(?i)\bTODO\b|mock_provider|override_|terraform_data|aws_vpc|aws_subnet|aws_sns|aws_ami|aws_instance|aws_launch_template') { throw 'Candidate is unfinished or contains a prohibited construct.' }
  $resources = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if (($resources -join '|') -cne 'aws_iam_role|aws_s3_bucket' -or [regex]::Matches($text, 'resource\s+"aws_').Count -ne 6) { throw 'Candidate must manage exactly three S3 buckets and three IAM roles.' }
  $data = @([regex]::Matches($text, 'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if (($data -join '|') -cne 'aws_caller_identity|aws_iam_policy_document') { throw "AWS data source set differs: $($data -join ',')." }
  $providers = Get-Content -LiteralPath (Join-Path $Root 'providers.tf') -Raw
  if ([regex]::Matches($providers, 'provider\s+"aws"\s*\{').Count -ne 3) { throw 'Exactly three root AWS provider blocks are required.' }
  foreach ($alias in @('primary', 'dr', 'audit')) { if ($providers -notmatch "alias\s*=\s*`"$alias`"") { throw "Provider alias is missing: $alias" } }
  foreach ($pattern in @('required_version\s*=\s*"~>\s*1\.6"', 'version\s*=\s*"~>\s*5\.100"', 'configuration_aliases\s*=\s*\[aws\.dr,\s*aws\.audit\]', 'aws\s*=\s*aws\.primary', 'aws\.dr\s*=\s*aws\.dr', 'aws\.audit\s*=\s*aws\.audit')) { if ($text -notmatch $pattern) { throw "Provider slot contract is missing: $pattern" } }
  foreach ($pattern in @('access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"', 'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true', 'skip_requesting_account_id\s*=\s*true', '(?m)^\s*iam\s*=\s*var\.localstack_endpoint\s*$', '(?m)^\s*s3\s*=\s*var\.localstack_endpoint\s*$', '(?m)^\s*sts\s*=\s*var\.localstack_endpoint\s*$')) { if ($providers -notmatch $pattern) { throw "Safe provider contract is missing: $pattern" } }
  if ($providers -match '(?m)^\s*(ec2|sns|sqs|lambda|dynamodb|kms)\s*=') { throw 'Provider contains an out-of-scope endpoint.' }
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

$health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get
foreach ($service in @('iam', 's3', 'sts')) { if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." } }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c42-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $tempRoot 'candidate'
$fixtures = Join-Path $tempRoot 'fixtures'
$runId = 'c42-' + [guid]::NewGuid().ToString('N').Substring(0, 10)
$vars = @("-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
$addresses = @(
  'module.routed_storage.aws_iam_role.audit', 'module.routed_storage.aws_iam_role.dr', 'module.routed_storage.aws_iam_role.primary',
  'module.routed_storage.aws_s3_bucket.audit', 'module.routed_storage.aws_s3_bucket.dr', 'module.routed_storage.aws_s3_bucket.primary'
)
$applied = $false
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED')) { $envBefore[$name] = [Environment]::GetEnvironmentVariable($name) }
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $env:AWS_EC2_METADATA_DISABLED = 'true'

try {
  Copy-Clean $candidateRoot $work
  Copy-Clean (Join-Path $labRoot 'fixtures') $fixtures
  New-Item -ItemType Directory -Path (Join-Path $work 'tests') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $work 'tests\canonical.tftest.hcl') -Force
  Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $work) | Out-Null
  Invoke-Native 'terraform' @("-chdir=$work", 'init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Invoke-Native 'terraform' @("-chdir=$work", 'validate', '-no-color') | Out-Null
  $tests = Invoke-Native 'terraform' @("-chdir=$work", 'test', '-no-color')
  if ($tests.Text -notmatch 'Success! 7 passed, 0 failed') { throw 'Canonical test result/count differs.' }
  Write-Host '[unit] 7/7 Terraform 1.6 normal plan runs passed.'
  if ($UnitOnly) { Write-Host 'PASS challenge-42 UnitOnly'; return }

  $initialPlan = Join-Path $tempRoot 'initial.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-input=false', '-no-color', "-out=$initialPlan") + $vars) | Out-Null
  $initial = Read-Plan $work $initialPlan
  $creates = @{}; foreach ($address in $addresses) { $creates[$address] = 'create' }
  Assert-Actions (Action-Map $initial) $creates 'Initial plan'

  $resources = @($initial.configuration.root_module.module_calls.routed_storage.module.resources)
  $expectedProviderKeys = @{
    'aws_iam_role.primary' = 'aws.primary'; 'aws_s3_bucket.primary' = 'aws.primary'
    'aws_iam_role.dr' = 'aws.dr'; 'aws_s3_bucket.dr' = 'aws.dr'
    'aws_iam_role.audit' = 'aws.audit'; 'aws_s3_bucket.audit' = 'aws.audit'
  }
  foreach ($resource in $resources | Where-Object { $_.address -like 'aws_*' -and $_.mode -eq 'managed' }) {
    if (-not $expectedProviderKeys.ContainsKey($resource.address) -or $resource.provider_config_key -ne $expectedProviderKeys[$resource.address]) { throw "Provider config key differs at $($resource.address): $($resource.provider_config_key)." }
  }
  if (@($resources | Where-Object { $_.address -like 'aws_*' -and $_.mode -eq 'managed' }).Count -ne 6) { throw 'Saved plan configuration must expose six routed managed resources.' }
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', '-no-color', $initialPlan) | Out-Null
  $applied = $true

  $outputs = (Invoke-Native 'terraform' @("-chdir=$work", 'output', '-json')).Text | ConvertFrom-Json
  foreach ($slot in @('primary', 'dr', 'audit')) {
    if ([string]$outputs.routing_contract.value.$slot.account_id -ne '000000000000') { throw "$slot caller identity differs." }
  }
  $expectedRegions = @{ primary = 'None'; dr = 'us-west-2'; audit = 'eu-west-1' }
  foreach ($slot in @('primary', 'dr', 'audit')) {
    $bucket = [string]$outputs.managed_contract.value.bucket_names.$slot
    $region = (Invoke-Aws 'us-east-1' @('s3api', 'get-bucket-location', '--bucket', $bucket, '--query', 'LocationConstraint', '--output', 'text')).Text.Trim()
    if ([string]::IsNullOrWhiteSpace($region)) { $region = 'None' }
    if ($region -ne $expectedRegions[$slot]) { throw "$slot bucket region differs: $region." }
    $role = [string]$outputs.routing_contract.value.$slot.role
    $remoteRole = (Invoke-Aws 'us-east-1' @('iam', 'get-role', '--role-name', $role, '--output', 'json')).Text | ConvertFrom-Json
    if ($remoteRole.Role.RoleName -ne $role) { throw "$slot role is missing." }
  }

  $reorder = Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-detailed-exitcode', '-input=false', '-no-color') + $vars + @('-var=routes_path=../fixtures/routes-reordered.json')) @(0, 2)
  if ($reorder.ExitCode -ne 0) { throw 'Reordered routes changed the graph.' }

  $auditRole = [string]$outputs.routing_contract.value.audit.role
  Invoke-Aws 'us-east-1' @('iam', 'tag-role', '--role-name', $auditRole, '--tags', 'Key=ProviderSlot,Value=drift') | Out-Null
  $repairPlan = Join-Path $tempRoot 'repair.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-input=false', '-no-color', "-out=$repairPlan") + $vars) | Out-Null
  Assert-Actions (Action-Map (Read-Plan $work $repairPlan)) @{ 'module.routed_storage.aws_iam_role.audit' = 'update' } 'Audit drift repair'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', '-no-color', $repairPlan) | Out-Null
  $clean = Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-detailed-exitcode', '-input=false', '-no-color') + $vars) @(0, 2)
  if ($clean.ExitCode -ne 0) { throw 'Post-repair plan is not clean.' }

  $destroyPlan = Join-Path $tempRoot 'destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-destroy', '-input=false', '-no-color', "-out=$destroyPlan") + $vars) | Out-Null
  $deletes = @{}; foreach ($address in $addresses) { $deletes[$address] = 'delete' }
  Assert-Actions (Action-Map (Read-Plan $work $destroyPlan)) $deletes 'Destroy plan'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', '-no-color', $destroyPlan) | Out-Null
  $applied = $false

  $buckets = (Invoke-Aws 'us-east-1' @('s3api', 'list-buckets', '--output', 'json')).Text | ConvertFrom-Json
  if (@($buckets.Buckets | Where-Object { $_.Name -like "$runId-*" }).Count -ne 0) { throw 'S3 residue remains.' }
  $roles = (Invoke-Aws 'us-east-1' @('iam', 'list-roles', '--output', 'json')).Text | ConvertFrom-Json
  if (@($roles.Roles | Where-Object { $_.RoleName -like "$runId-*" }).Count -ne 0) { throw 'IAM residue remains.' }
  Write-Host 'PASS challenge-42: 7/7 tests, six provider-key routes, three regions, reorder, IAM drift repair, saved destroy, zero residue.'
}
finally {
  if ($applied -and (Test-Path $work)) { try { Invoke-Native 'terraform' (@("-chdir=$work", 'destroy', '-auto-approve', '-input=false', '-no-color') + $vars) @(0, 1) | Out-Null } catch {} }
  foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
