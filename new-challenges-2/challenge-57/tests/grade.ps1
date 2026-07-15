[CmdletBinding()]
param(
  [string]$Candidate = '',
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)

if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $lines = @(& $File @Arguments 2>&1)
    $code = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $old
  }
  $value = $lines -join [Environment]::NewLine
  if ($code -notin $Allowed) { throw "$File $($Arguments -join ' ') exited $code.`n$value" }
  return [pscustomobject]@{ ExitCode = $code; Text = $value }
}

function Invoke-Terraform([string]$Root, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  return Invoke-Native 'terraform' (@("-chdir=$Root") + $Arguments) $Allowed
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
  $text = (Invoke-Terraform $Root @('show', '-json', $Path)).Text
  $start = $text.IndexOf('{"format_version"', [StringComparison]::Ordinal)
  if ($start -lt 0) { throw "terraform show did not return plan JSON for $Path." }
  return ($text.Substring($start) | ConvertFrom-Json)
}

function Get-ActionMap([object]$Plan) {
  $map = @{}
  foreach ($change in @($Plan.resource_changes | Where-Object { $_.mode -eq 'managed' })) {
    $action = @($change.change.actions) -join ','
    if ($action -notin @('no-op', 'read')) { $map[$change.address] = $action }
  }
  return $map
}

function Assert-ExactMap([hashtable]$Actual, [hashtable]$Expected, [string]$Label) {
  if ($Actual.Count -ne $Expected.Count) { throw "$Label action count differs: actual=$($Actual.Count), expected=$($Expected.Count)." }
  foreach ($address in $Expected.Keys) {
    if (-not $Actual.ContainsKey($address) -or $Actual[$address] -ne $Expected[$address]) {
      throw "$Label action differs at ${address}: $($Actual[$address])."
    }
  }
}

function Assert-Tag([object[]]$Tags, [string]$Key, [string]$Value, [string]$Label) {
  if (@($Tags | Where-Object { $_.Key -eq $Key -and $_.Value -eq $Value }).Count -ne 1) {
    throw "$Label lacks exactly one $Key=$Value tag."
  }
}

function Assert-Candidate([string]$Root) {
  $files = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File)
  if ($files.Count -ne 9 -or @($files | Where-Object { $_.Extension -ne '.tf' }).Count -ne 0) {
    throw 'Candidate must contain exactly nine Terraform HCL files and no generated lock file.'
  }
  foreach ($file in $files) {
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Candidate HCL cannot be a reparse point: $($file.FullName)" }
  }
  $text = ($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
  if ($text -match '(?i)\bTODO\b|FIXME|CHANGEME|mock_provider|override_|terraform_data|ignore_changes|aws_(?:vpc|subnet|iam|sns|sqs|instance|dynamodb)') {
    throw 'Candidate is unfinished or contains a prohibited workaround or AWS type.'
  }

  $resources = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $data = @([regex]::Matches($text, 'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if (($resources -join '|') -cne 'aws_s3_bucket|aws_s3_object' -or [regex]::Matches($text, 'resource\s+"aws_').Count -ne 4) {
    throw "Managed AWS resource contract differs: $($resources -join ',')."
  }
  if (($data -join '|') -cne 'aws_caller_identity' -or [regex]::Matches($text, 'data\s+"aws_').Count -ne 2) {
    throw "AWS data source contract differs: $($data -join ',')."
  }

  $rootVersions = Get-Content -LiteralPath (Join-Path $Root 'versions.tf') -Raw
  $childVersions = Get-Content -LiteralPath (Join-Path $Root 'modules\dual_release\versions.tf') -Raw
  $rootMain = Get-Content -LiteralPath (Join-Path $Root 'main.tf') -Raw
  $providers = Get-Content -LiteralPath (Join-Path $Root 'providers.tf') -Raw
  if ($rootVersions -notmatch 'required_version\s*=\s*"~>\s*1\.6\.0"' -or $rootVersions -notmatch 'version\s*=\s*"~>\s*5\.100\.0"') {
    throw 'Root Terraform or AWS provider version boundary differs.'
  }
  if ($childVersions -notmatch 'required_version\s*=\s*">=\s*1\.6\.0,\s*<\s*1\.7\.0"' -or
    $childVersions -notmatch 'version\s*=\s*">=\s*5\.90\.0,\s*<\s*6\.0\.0"' -or
    $childVersions -notmatch 'configuration_aliases\s*=\s*\[aws\.primary,\s*aws\.replica\]') {
    throw 'Child module version or provider-slot contract differs.'
  }
  foreach ($pattern in @(
      'aws\.primary\s*=\s*aws\.primary',
      'aws\.replica\s*=\s*aws\.replica',
      'for_each\s*=\s*local\.releases'
    )) {
    if ($rootMain -notmatch $pattern) { throw "Root module routing token is missing: $pattern" }
  }
  if ([regex]::Matches($providers, 'provider\s+"aws"\s*\{').Count -ne 2 -or
    [regex]::Matches($providers, 'alias\s*=\s*"primary"').Count -ne 1 -or
    [regex]::Matches($providers, 'alias\s*=\s*"replica"').Count -ne 1) {
    throw 'Exactly two aliased root AWS providers are required.'
  }
  foreach ($token in @(
      'access_key                  = "test"',
      'secret_key                  = "test"',
      's3_use_path_style           = true',
      'skip_credentials_validation = true',
      'skip_metadata_api_check     = true',
      'skip_requesting_account_id  = true'
    )) {
    if ([regex]::Matches($providers, [regex]::Escape($token)).Count -ne 2) { throw "Provider safety token must appear twice: $token" }
  }
  if ([regex]::Matches($providers, '(?m)^\s*s3\s*=\s*var\.localstack_endpoint\s*$').Count -ne 2 -or
    [regex]::Matches($providers, '(?m)^\s*sts\s*=\s*var\.localstack_endpoint\s*$').Count -ne 2 -or
    $providers -match '(?m)^\s*(?:ec2|iam|sns|sqs|dynamodb|kms|lambda)\s*=') {
    throw 'Provider endpoint set must be exactly S3 and STS for both slots.'
  }
  if ([regex]::Matches($text, 'provider\s*=\s*aws\.primary').Count -ne 3 -or
    [regex]::Matches($text, 'provider\s*=\s*aws\.replica').Count -ne 3) {
    throw 'All six child AWS blocks must bind to an explicit provider slot.'
  }
}

# Endpoint validation intentionally precedes filesystem resolution and every external command.
Assert-Endpoint $LocalstackEndpoint
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
Assert-Candidate $candidateRoot
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw 'terraform is required.' }
if ($null -eq (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI is required.' }
$terraformVersion = (Invoke-Native 'terraform' @('version', '-json')).Text | ConvertFrom-Json
if ($terraformVersion.terraform_version -ne '1.6.6') { throw "Terraform 1.6.6 is required; got $($terraformVersion.terraform_version)." }

$labRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$canonical = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Raw
if ($canonical -match '(?i)mock_provider|override_' -or [regex]::Matches($canonical, '(?m)^\s*run\s+"').Count -ne 13) {
  throw 'Canonical suite must contain exactly 13 normal Terraform 1.6 runs.'
}

$runId = 'c57-' + [guid]::NewGuid().ToString('N').Substring(0, 10)
$prefix = "tfpro-$runId-"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c57-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $tempRoot 'candidate'
$fixtures = Join-Path $tempRoot 'fixtures'
$base = @("-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
$v1 = $base + @('-var=catalog_path=../fixtures/releases-v1.json')
$v1Reordered = $base + @('-var=catalog_path=../fixtures/releases-v1-reordered.json')
$v2 = $base + @('-var=catalog_path=../fixtures/releases-v2.json')
$addresses = @()
foreach ($name in @('api', 'worker')) {
  foreach ($resource in @('aws_s3_bucket.primary', 'aws_s3_bucket.replica', 'aws_s3_object.primary', 'aws_s3_object.replica')) {
    $addresses += "module.release[`"$name`"].$resource"
  }
}
$applied = $false
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED')) {
  $envBefore[$name] = [Environment]::GetEnvironmentVariable($name)
}
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
$env:AWS_EC2_METADATA_DISABLED = 'true'

try {
  Copy-Clean $candidateRoot $work
  Copy-Clean (Join-Path $labRoot 'fixtures') $fixtures
  New-Item -ItemType Directory -Path (Join-Path $work 'tests') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $work 'tests\canonical.tftest.hcl') -Force
  Copy-Item -LiteralPath (Join-Path $fixtures 'stale-lock.fixture.hcl') -Destination (Join-Path $work '.terraform.lock.hcl') -Force

  $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get -TimeoutSec 5
  foreach ($service in @('s3', 'sts')) {
    if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." }
  }

  Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $work) | Out-Null
  $readonlyFailure = Invoke-Terraform $work @('init', '-backend=false', '-input=false', '-no-color', '-lockfile=readonly') @(0, 1)
  $readonlyNormalized = $readonlyFailure.Text -replace '\s+', ' '
  if ($readonlyFailure.ExitCode -eq 0 -or $readonlyNormalized -notmatch '5\.99\.0' -or
    $readonlyNormalized -notmatch 'does not match configured version constraint' -or $readonlyNormalized -notmatch 'init -upgrade') {
    throw "Readonly init did not reject the stale provider selection for the expected reason.`n$($readonlyFailure.Text)"
  }

  Invoke-Terraform $work @('init', '-backend=false', '-input=false', '-no-color', '-upgrade') | Out-Null
  $lockText = Get-Content -LiteralPath (Join-Path $work '.terraform.lock.hcl') -Raw
  if ($lockText -notmatch 'provider\s+"registry\.terraform\.io/hashicorp/aws"' -or
    $lockText -notmatch 'version\s*=\s*"5\.100\.0"' -or $lockText -match 'version\s*=\s*"5\.99\.0"' -or
    $lockText -notmatch 'constraints\s*=\s*"[^"]*5\.90\.0[^"]*5\.100\.0[^"]*6\.0\.0') {
    throw 'Upgraded lock file does not record provider 5.100.0 and the combined root/child boundaries.'
  }
  $selected = (Invoke-Terraform $work @('version', '-json')).Text | ConvertFrom-Json
  if ([string]$selected.provider_selections.'registry.terraform.io/hashicorp/aws' -ne '5.100.0') {
    throw 'Terraform does not report AWS provider 5.100.0 as the selected lock version.'
  }
  Invoke-Terraform $work @('init', '-backend=false', '-input=false', '-no-color', '-lockfile=readonly') | Out-Null
  Invoke-Terraform $work @('validate', '-no-color') | Out-Null
  $tests = Invoke-Terraform $work @('test', '-test-directory=tests', '-no-color')
  if ([regex]::Matches($tests.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 13 -or
    $tests.Text -notmatch '(?m)^Success!\s+13 passed,\s+0 failed\.\s*$') {
    throw "Expected exact 13/13 normal Terraform tests.`n$($tests.Text)"
  }
  Write-Host '[unit] stale readonly failure, explicit lock upgrade to 5.100.0, readonly replay, and 13/13 normal tests passed.'
  if ($UnitOnly) { Write-Host 'PASS challenge-57 UnitOnly'; return }

  Remove-Item -LiteralPath (Join-Path $work 'tests') -Recurse -Force
  $initialPlan = Join-Path $tempRoot 'initial.tfplan'
  Invoke-Terraform $work (@('plan', '-input=false', '-no-color', "-out=$initialPlan") + $v1) | Out-Null
  $initial = Read-Plan $work $initialPlan
  $creates = @{}
  foreach ($address in $addresses) { $creates[$address] = 'create' }
  Assert-ExactMap (Get-ActionMap $initial) $creates 'Initial rollout'

  $configured = @($initial.configuration.root_module.module_calls.release.module.resources)
  $providerKeys = @{
    'data.aws_caller_identity.primary' = 'aws.primary'
    'data.aws_caller_identity.replica' = 'aws.replica'
    'aws_s3_bucket.primary'            = 'aws.primary'
    'aws_s3_bucket.replica'            = 'aws.replica'
    'aws_s3_object.primary'            = 'aws.primary'
    'aws_s3_object.replica'            = 'aws.replica'
  }
  if ($configured.Count -ne 6) { throw "Saved configuration exposes $($configured.Count) child AWS blocks instead of six." }
  foreach ($resource in $configured) {
    if (-not $providerKeys.ContainsKey($resource.address) -or $resource.provider_config_key -ne $providerKeys[$resource.address]) {
      throw "Provider config key differs at $($resource.address): $($resource.provider_config_key)."
    }
  }

  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $initialPlan) | Out-Null
  $applied = $true
  $v1Contract = (Invoke-Terraform $work @('output', '-json', 'routing_contract')).Text | ConvertFrom-Json
  $payloadsV1 = @{ api = 'api-release-v1'; worker = 'worker-release-v1' }
  foreach ($name in @('api', 'worker')) {
    foreach ($slot in @('primary', 'replica')) {
      $entry = $v1Contract.releases.$name.$slot
      if ([string]$entry.account_id -ne '000000000000') { throw "$name/$slot caller identity differs." }
      $expectedRegion = if ($slot -eq 'primary') { 'None' } else { 'us-west-2' }
      $region = if ($slot -eq 'primary') { 'us-east-1' } else { 'us-west-2' }
      $actualRegion = (Invoke-Aws $region @('s3api', 'get-bucket-location', '--bucket', $entry.bucket_name, '--query', 'LocationConstraint', '--output', 'text')).Text.Trim()
      if ([string]::IsNullOrWhiteSpace($actualRegion)) { $actualRegion = 'None' }
      if ($actualRegion -ne $expectedRegion) { throw "$name/$slot bucket region differs: $actualRegion." }
      $body = Join-Path $tempRoot "$name-$slot-v1.txt"
      Invoke-Aws $region @('s3api', 'get-object', '--bucket', $entry.bucket_name, '--key', $entry.object_key, $body) | Out-Null
      if ((Get-Content -LiteralPath $body -Raw) -cne $payloadsV1[$name]) { throw "$name/$slot object body differs." }
      $bucketTags = ((Invoke-Aws $region @('s3api', 'get-bucket-tagging', '--bucket', $entry.bucket_name, '--output', 'json')).Text | ConvertFrom-Json).TagSet
      Assert-Tag @($bucketTags) 'ProviderSlot' $slot "$name/$slot bucket"
      Assert-Tag @($bucketTags) 'RunId' $runId "$name/$slot bucket"
      $objectTags = ((Invoke-Aws $region @('s3api', 'get-object-tagging', '--bucket', $entry.bucket_name, '--key', $entry.object_key, '--output', 'json')).Text | ConvertFrom-Json).TagSet
      Assert-Tag @($objectTags) 'ProviderSlot' $slot "$name/$slot object"
      Assert-Tag @($objectTags) 'Release' $name "$name/$slot object"
    }
  }

  $reorder = Invoke-Terraform $work (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $v1Reordered) @(0, 2)
  if ($reorder.ExitCode -ne 0) { throw "Catalog reorder changed the graph.`n$($reorder.Text)" }

  $v2Plan = Join-Path $tempRoot 'v2.tfplan'
  Invoke-Terraform $work (@('plan', '-input=false', '-no-color', "-out=$v2Plan") + $v2) | Out-Null
  Assert-ExactMap (Get-ActionMap (Read-Plan $work $v2Plan)) @{
    'module.release["api"].aws_s3_object.primary' = 'update'
    'module.release["api"].aws_s3_object.replica' = 'update'
  } 'V2 rollout'
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $v2Plan) | Out-Null
  $v2Contract = (Invoke-Terraform $work @('output', '-json', 'routing_contract')).Text | ConvertFrom-Json
  foreach ($name in @('api', 'worker')) {
    foreach ($slot in @('primary', 'replica')) {
      foreach ($field in @('bucket_name', 'bucket_arn', 'object_key', 'object_id')) {
        if ([string]$v1Contract.releases.$name.$slot.$field -cne [string]$v2Contract.releases.$name.$slot.$field) {
          throw "$name/$slot $field changed during the content-only rollout."
        }
      }
      $region = if ($slot -eq 'primary') { 'us-east-1' } else { 'us-west-2' }
      $expected = if ($name -eq 'api') { 'api-release-v2' } else { 'worker-release-v1' }
      $body = Join-Path $tempRoot "$name-$slot-v2.txt"
      Invoke-Aws $region @('s3api', 'get-object', '--bucket', $v2Contract.releases.$name.$slot.bucket_name, '--key', $v2Contract.releases.$name.$slot.object_key, $body) | Out-Null
      if ((Get-Content -LiteralPath $body -Raw) -cne $expected) { throw "$name/$slot V2 object body differs." }
    }
  }

  $victim = $v2Contract.releases.worker.replica
  $tampered = Join-Path $tempRoot 'tampered.txt'
  [IO.File]::WriteAllText($tampered, 'tampered', [Text.UTF8Encoding]::new($false))
  Invoke-Aws 'us-west-2' @('s3api', 'put-object', '--bucket', $victim.bucket_name, '--key', $victim.object_key, '--body', $tampered) | Out-Null
  $repairPlan = Join-Path $tempRoot 'repair.tfplan'
  Invoke-Terraform $work (@('plan', '-input=false', '-no-color', "-out=$repairPlan") + $v2) | Out-Null
  Assert-ExactMap (Get-ActionMap (Read-Plan $work $repairPlan)) @{
    'module.release["worker"].aws_s3_object.replica' = 'update'
  } 'Replica object drift repair'
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $repairPlan) | Out-Null
  $restored = Join-Path $tempRoot 'worker-replica-restored.txt'
  Invoke-Aws 'us-west-2' @('s3api', 'get-object', '--bucket', $victim.bucket_name, '--key', $victim.object_key, $restored) | Out-Null
  if ((Get-Content -LiteralPath $restored -Raw) -cne 'worker-release-v1') { throw 'Replica object drift was not repaired.' }

  $clean = Invoke-Terraform $work (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $v2) @(0, 2)
  if ($clean.ExitCode -ne 0) { throw "Post-repair plan is not clean.`n$($clean.Text)" }

  $destroyPlan = Join-Path $tempRoot 'destroy.tfplan'
  Invoke-Terraform $work (@('plan', '-destroy', '-input=false', '-no-color', "-out=$destroyPlan") + $v2) | Out-Null
  $deletes = @{}
  foreach ($address in $addresses) { $deletes[$address] = 'delete' }
  Assert-ExactMap (Get-ActionMap (Read-Plan $work $destroyPlan)) $deletes 'Destroy plan'
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $destroyPlan) | Out-Null
  $applied = $false
  if (-not [string]::IsNullOrWhiteSpace((Invoke-Terraform $work @('state', 'list')).Text)) { throw 'Terraform state is not empty after destroy.' }

  $buckets = ((Invoke-Aws 'us-east-1' @('s3api', 'list-buckets', '--output', 'json')).Text | ConvertFrom-Json).Buckets
  if (@($buckets | Where-Object { $_.Name -like "$prefix*" }).Count -ne 0) { throw 'Challenge 57 S3 residue remains.' }
  Write-Host 'PASS challenge-57: lock mismatch/upgrade, 13/13 tests, six provider-key routes, dual-region readback, scoped rollout, drift repair, saved destroy, zero residue.'
}
finally {
  if ($applied -and (Test-Path -LiteralPath $work)) {
    try { Invoke-Terraform $work (@('destroy', '-auto-approve', '-input=false', '-no-color') + $v2) @(0, 1) | Out-Null } catch {}
  }
  try {
    $remaining = ((Invoke-Aws 'us-east-1' @('s3api', 'list-buckets', '--output', 'json')).Text | ConvertFrom-Json).Buckets
    foreach ($bucket in @($remaining | Where-Object { $_.Name -like "$prefix*" })) {
      try { Invoke-Aws 'us-east-1' @('s3', 'rb', "s3://$($bucket.Name)", '--force') @(0, 1) | Out-Null } catch {}
    }
  }
  catch {}
  foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
