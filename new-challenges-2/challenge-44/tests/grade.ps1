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
    if (-not $Actual.ContainsKey($address) -or $Actual[$address] -ne $Expected[$address]) { throw "$Label action differs at ${address}: $($Actual[$address])." }
  }
}

function Get-Strings([object]$Value) {
  if ($null -eq $Value) { return @() }
  if ($Value -is [string]) { return @([string]$Value) }
  return @($Value | ForEach-Object { [string]$_ })
}

function Assert-Candidate([string]$Root) {
  $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.tf')
  if ($files.Count -eq 0 -or @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1').Count -ne 0) { throw 'Candidate must contain Terraform HCL only.' }
  $text = ($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
  if ($text -match '(?i)\bTODO\b|mock_provider|override_|terraform_data|aws_sns|aws_vpc|aws_subnet|aws_instance|aws_launch_template') { throw 'Candidate is unfinished or contains a prohibited construct.' }
  $resources = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $expectedResources = 'aws_iam_policy|aws_iam_role|aws_iam_role_policy_attachment|aws_s3_bucket|aws_s3_object'
  if (($resources -join '|') -cne $expectedResources -or [regex]::Matches($text, 'resource\s+"aws_').Count -ne 5) { throw "Managed AWS resource contract differs: $($resources -join ',')." }
  $data = @([regex]::Matches($text, 'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if (($data -join '|') -cne 'aws_iam_policy_document') { throw "AWS data source set differs: $($data -join ',')." }
  if ($text -notmatch 'dynamic\s+"statement"' -and $text -notmatch 'data\s+"aws_iam_policy_document"\s+"access"') { throw 'IAM policy must be compiled with aws_iam_policy_document.' }
  foreach ($pattern in @('required_version\s*=\s*"~>\s*1\.6"', 'version\s*=\s*"~>\s*5\.100"', 'access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"', 'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true', 'skip_requesting_account_id\s*=\s*true', '(?m)^\s*iam\s*=\s*var\.localstack_endpoint\s*$', '(?m)^\s*s3\s*=\s*var\.localstack_endpoint\s*$', '(?m)^\s*sts\s*=\s*var\.localstack_endpoint\s*$')) { if ($text -notmatch $pattern) { throw "Candidate contract is missing: $pattern" } }
  if ($text -match '(?m)^\s*(ec2|sns|sqs|lambda|dynamodb|kms)\s*=') { throw 'Provider contains an out-of-scope endpoint.' }
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
if ($canonical -match '(?i)mock_provider|override_' -or [regex]::Matches($canonical, '(?m)^\s*run\s+"').Count -ne 9) { throw 'Canonical suite must contain exactly nine normal Terraform 1.6 runs.' }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c44-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $tempRoot 'candidate'
$fixtures = Join-Path $tempRoot 'fixtures'
$runId = 'c44-' + [guid]::NewGuid().ToString('N').Substring(0, 10)
$base = @("-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
$v1 = $base + @('-var=catalog_path=../fixtures/catalog-v1.json')
$v1Reordered = $base + @('-var=catalog_path=../fixtures/catalog-v1-reordered.json')
$v2 = $base + @('-var=catalog_path=../fixtures/catalog-v2.json')
$addresses = @()
foreach ($name in @('api', 'worker')) {
  foreach ($resource in @('aws_iam_policy.access', 'aws_iam_role.consumer', 'aws_iam_role_policy_attachment.access', 'aws_s3_bucket.release', 'aws_s3_object.release')) {
    $addresses += "module.release_bundle[`"$name`"].$resource"
  }
}
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
  if ($tests.Text -notmatch 'Success! 9 passed, 0 failed') { throw 'Canonical test result/count differs.' }
  Write-Host '[unit] 9/9 Terraform 1.6 normal plan runs passed.'
  if ($UnitOnly) { Write-Host 'PASS challenge-44 UnitOnly'; return }

  $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get
  foreach ($service in @('iam', 's3', 'sts')) { if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." } }

  $initialPlan = Join-Path $tempRoot 'v1.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-input=false', '-no-color', "-out=$initialPlan") + $v1) | Out-Null
  $creates = @{}; foreach ($address in $addresses) { $creates[$address] = 'create' }
  Assert-Actions (Action-Map (Read-Plan $work $initialPlan)) $creates 'V1 plan'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', '-no-color', $initialPlan) | Out-Null
  $applied = $true
  $v1Contract = (Invoke-Native 'terraform' @("-chdir=$work", 'output', '-json', 'managed_contract')).Text | ConvertFrom-Json

  foreach ($name in @('api', 'worker')) {
    $entry = $v1Contract.$name
    $bodyPath = Join-Path $tempRoot "$name-v1.txt"
    Invoke-Aws @('s3api', 'get-object', '--bucket', $entry.bucket_name, '--key', $entry.object_key, $bodyPath) | Out-Null
    if ((Get-Content -LiteralPath $bodyPath -Raw) -cne "$name-release-v1") { throw "$name V1 object content differs." }
    $meta = (Invoke-Aws @('iam', 'get-policy', '--policy-arn', $entry.policy_arn, '--output', 'json')).Text | ConvertFrom-Json
    $version = (Invoke-Aws @('iam', 'get-policy-version', '--policy-arn', $entry.policy_arn, '--version-id', $meta.Policy.DefaultVersionId, '--output', 'json')).Text | ConvertFrom-Json
    $actions = @(Get-Strings $version.PolicyVersion.Document.Statement.Action | Sort-Object)
    if (($actions -join ',') -cne 's3:GetObject') { throw "$name V1 policy actions differ." }
  }

  $reorder = Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-detailed-exitcode', '-input=false', '-no-color') + $v1Reordered) @(0, 2)
  if ($reorder.ExitCode -ne 0) { throw 'V1 reorder changed the graph.' }

  $v2Plan = Join-Path $tempRoot 'v2.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-input=false', '-no-color', "-out=$v2Plan") + $v2) | Out-Null
  $updates = @{}
  foreach ($name in @('api', 'worker')) {
    $updates["module.release_bundle[`"$name`"].aws_s3_object.release"] = 'update'
    $updates["module.release_bundle[`"$name`"].aws_iam_policy.access"] = 'update'
  }
  Assert-Actions (Action-Map (Read-Plan $work $v2Plan)) $updates 'V2 interface rollout'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', '-no-color', $v2Plan) | Out-Null
  $v2Contract = (Invoke-Native 'terraform' @("-chdir=$work", 'output', '-json', 'managed_contract')).Text | ConvertFrom-Json

  foreach ($name in @('api', 'worker')) {
    $before = $v1Contract.$name; $after = $v2Contract.$name
    foreach ($field in @('bucket_name', 'object_key', 'object_id', 'role_arn', 'policy_arn')) { if ([string]$before.$field -cne [string]$after.$field) { throw "$name $field rolled during interface evolution." } }
    $bodyPath = Join-Path $tempRoot "$name-v2.txt"
    Invoke-Aws @('s3api', 'get-object', '--bucket', $after.bucket_name, '--key', $after.object_key, $bodyPath) | Out-Null
    if ((Get-Content -LiteralPath $bodyPath -Raw) -cne "$name-release-v2") { throw "$name V2 object content differs." }
    $meta = (Invoke-Aws @('iam', 'get-policy', '--policy-arn', $after.policy_arn, '--output', 'json')).Text | ConvertFrom-Json
    $version = (Invoke-Aws @('iam', 'get-policy-version', '--policy-arn', $after.policy_arn, '--version-id', $meta.Policy.DefaultVersionId, '--output', 'json')).Text | ConvertFrom-Json
    $actions = @(Get-Strings $version.PolicyVersion.Document.Statement.Action | Sort-Object)
    if (($actions -join ',') -cne 's3:GetObject,s3:GetObjectVersion') { throw "$name V2 policy actions differ." }
  }

  $worker = $v2Contract.worker
  Invoke-Aws @('iam', 'detach-role-policy', '--role-name', $worker.role_name, '--policy-arn', $worker.policy_arn) | Out-Null
  $repairPlan = Join-Path $tempRoot 'repair.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-input=false', '-no-color', "-out=$repairPlan") + $v2) | Out-Null
  Assert-Actions (Action-Map (Read-Plan $work $repairPlan)) @{ 'module.release_bundle["worker"].aws_iam_role_policy_attachment.access' = 'create' } 'Attachment drift repair'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', '-no-color', $repairPlan) | Out-Null
  $clean = Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-detailed-exitcode', '-input=false', '-no-color') + $v2) @(0, 2)
  if ($clean.ExitCode -ne 0) { throw 'Post-repair plan is not clean.' }

  $destroyPlan = Join-Path $tempRoot 'destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-destroy', '-input=false', '-no-color', "-out=$destroyPlan") + $v2) | Out-Null
  $deletes = @{}; foreach ($address in $addresses) { $deletes[$address] = 'delete' }
  Assert-Actions (Action-Map (Read-Plan $work $destroyPlan)) $deletes 'Destroy plan'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', '-no-color', $destroyPlan) | Out-Null
  $applied = $false

  $buckets = (Invoke-Aws @('s3api', 'list-buckets', '--output', 'json')).Text | ConvertFrom-Json
  $roles = (Invoke-Aws @('iam', 'list-roles', '--output', 'json')).Text | ConvertFrom-Json
  $policies = (Invoke-Aws @('iam', 'list-policies', '--scope', 'Local', '--output', 'json')).Text | ConvertFrom-Json
  if (@($buckets.Buckets | Where-Object { $_.Name -like "$runId-*" }).Count -ne 0 -or @($roles.Roles | Where-Object { $_.RoleName -like "$runId-*" }).Count -ne 0 -or @($policies.Policies | Where-Object { $_.PolicyName -like "$runId-*" }).Count -ne 0) { throw 'S3 or IAM residue remains.' }
  Write-Host 'PASS challenge-44: 9/9 tests, exact four-update V2 rollout, stable IDs, attachment drift repair, saved destroy, zero residue.'
}
finally {
  if ($applied -and (Test-Path $work)) { try { Invoke-Native 'terraform' (@("-chdir=$work", 'destroy', '-auto-approve', '-input=false', '-no-color') + $v2) @(0, 1) | Out-Null } catch {} }
  foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
