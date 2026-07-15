[CmdletBinding()]
param(
  [string]$Candidate = '',
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)
if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Assert-Endpoint([string]$Endpoint) {
  $uri = $null
  $match = [regex]::Match($Endpoint, '\Ahttp://(?:localhost|127\.0\.0\.1|\[::1\]):(?<port>[1-9][0-9]{0,4})\z')
  if ([string]::IsNullOrEmpty($Endpoint) -or $Endpoint.Contains("`r") -or $Endpoint.Contains("`n") -or -not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or -not [string]::IsNullOrEmpty($uri.UserInfo) -or $uri.PathAndQuery -ne '/') { throw 'LocalstackEndpoint must be an explicit loopback HTTP root origin with a valid port.' }
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  $old = $ErrorActionPreference
  try { $ErrorActionPreference = 'Continue'; $lines = @(& $File @Arguments 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE }
  finally { $ErrorActionPreference = $old }
  $value = $lines -join [Environment]::NewLine
  if ($code -notin $Allowed) { throw "$File $($Arguments -join ' ') exited $code.`n$value" }
  return [pscustomobject]@{ ExitCode = $code; Text = $value }
}

function Invoke-Aws([string[]]$Arguments, [int[]]$Allowed = @(0)) {
  return Invoke-Native 'aws' (@('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1') + $Arguments) $Allowed
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
  if ($start -lt 0) { throw "terraform show did not return plan JSON for $Path." }
  return ($text.Substring($start) | ConvertFrom-Json)
}

function Assert-Plan([string]$Root, [string]$Plan, [hashtable]$Expected, [string]$Label) {
  $json = Read-Plan $Root $Plan
  $changed = @($json.resource_changes | Where-Object { $_.mode -eq 'managed' -and (@($_.change.actions) -join ',') -ne 'no-op' })
  if ($changed.Count -ne $Expected.Count) { throw "$Label action count differs: actual=$($changed.Count), expected=$($Expected.Count)." }
  foreach ($change in $changed) {
    $action = @($change.change.actions) -join ','
    if (-not $Expected.ContainsKey($change.address) -or $Expected[$change.address] -ne $action -or $change.type -notin @('aws_s3_bucket', 'aws_s3_object')) { throw "$Label action/type differs at $($change.address): $action." }
  }
}

function Assert-Candidate([string]$Root) {
  if (@(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1').Count -ne 0) { throw 'Candidate scripts are prohibited.' }
  foreach ($name in @('producer', 'consumer')) {
    $dir = Join-Path $Root $name
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "Missing $name root." }
    $files = @(Get-ChildItem -LiteralPath $dir -File -Filter '*.tf')
    if ($files.Count -ne 6) { throw "$name must contain exactly six Terraform files." }
    $text = ($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    if ($text -match '(?i)\bTODO\b|mock_provider|override_|terraform_data|backend\s+"local"|aws_sns|aws_vpc|aws_subnet|aws_instance') { throw "$name contains an unfinished or prohibited construct." }
    if ($text -notmatch 'required_version\s*=\s*"~>\s*1\.6"' -or $text -notmatch 'version\s*=\s*"~>\s*5\.100') { throw "$name version constraints differ." }
    if ($text -notmatch 'backend\s+"s3"\s*\{\s*\}') { throw "$name must declare a partial S3 backend." }
    foreach ($pattern in @('access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"', 'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true', 'skip_requesting_account_id\s*=\s*true', '(?m)^\s*s3\s*=\s*var\.localstack_endpoint\s*$', '(?m)^\s*sts\s*=\s*var\.localstack_endpoint\s*$')) { if ($text -notmatch $pattern) { throw "$name provider contract is missing: $pattern" } }
    $types = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if (($types -join '|') -cne 'aws_s3_bucket|aws_s3_object') { throw "$name managed AWS type set differs: $($types -join ',')." }
  }
  $producerText = (Get-ChildItem (Join-Path $Root 'producer') -File -Filter '*.tf' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  $consumerText = (Get-ChildItem (Join-Path $Root 'consumer') -File -Filter '*.tf' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  if ([regex]::Matches($producerText, 'resource\s+"aws_').Count -ne 2 -or [regex]::Matches($consumerText, 'resource\s+"aws_').Count -ne 2) { throw 'Each root must declare exactly one S3 bucket and one S3 object block.' }
  if ($consumerText -notmatch 'data\s+"terraform_remote_state"\s+"producer"' -or $consumerText -notmatch 'backend\s*=\s*"s3"' -or $consumerText -notmatch 'endpoints\s*=\s*\{\s*s3\s*=\s*var\.localstack_endpoint' -or $consumerText -notmatch 'use_path_style\s*=\s*true') { throw 'Consumer S3 remote-state isolation contract is incomplete.' }
}

Assert-Endpoint $LocalstackEndpoint
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw 'terraform is required.' }
$terraformVersion = (& terraform version -json | ConvertFrom-Json).terraform_version
if ($LASTEXITCODE -ne 0 -or $terraformVersion -ne '1.6.6') { throw "Terraform 1.6.6 is required; active version is $terraformVersion." }
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
Assert-Candidate $candidateRoot
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'producer.tftest.hcl') -Raw
if ($testText -match '(?i)mock_provider|override_' -or [regex]::Matches($testText, '(?m)^\s*run\s+"').Count -ne 7) { throw 'Canonical suite must contain exactly seven normal Terraform 1.6 runs.' }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c45-' + [guid]::NewGuid().ToString('N'))
$candidateWork = Join-Path $scratch 'candidate'
$fixtures = Join-Path $scratch 'fixtures'
$producer = Join-Path $candidateWork 'producer'
$consumer = Join-Path $candidateWork 'consumer'
$suffix = [guid]::NewGuid().ToString('N').Substring(0, 10)
$runId = "c45-$suffix"
$stateBucket = "tfpro-c45-state-$suffix"
$legacyKey = 'legacy/producer.tfstate'
$producerKey = 'producer/terraform.tfstate'
$consumerKey = 'consumer/terraform.tfstate'
$commonProducer = @('-input=false', '-no-color', "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
$v1Producer = $commonProducer + @("-var-file=$(Join-Path $fixtures 'release-v1.tfvars.json')")
$v1Reordered = $commonProducer + @("-var-file=$(Join-Path $fixtures 'release-v1-reordered.tfvars.json')")
$v2Producer = $commonProducer + @("-var-file=$(Join-Path $fixtures 'release-v2.tfvars.json')")
$commonConsumer = @('-input=false', '-no-color', "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=state_bucket=$stateBucket", "-var=producer_state_key=$producerKey")
$v1Consumer = $commonConsumer + @('-var=expected_release_version=v1')
$v2Consumer = $commonConsumer + @('-var=expected_release_version=v2')
$producerInitialized = $false
$consumerInitialized = $false
$stateCreated = $false
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED')) { $envBefore[$name] = [Environment]::GetEnvironmentVariable($name) }

try {
  Copy-Clean $candidateRoot $candidateWork
  Copy-Clean (Join-Path $labRoot 'fixtures') $fixtures
  New-Item -ItemType Directory -Path (Join-Path $producer 'tests') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'producer.tftest.hcl') -Destination (Join-Path $producer 'tests\producer.tftest.hcl') -Force
  Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $candidateWork) | Out-Null
  Invoke-Native 'terraform' @("-chdir=$producer", 'init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Invoke-Native 'terraform' @("-chdir=$consumer", 'init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Invoke-Native 'terraform' @("-chdir=$producer", 'validate', '-no-color') | Out-Null
  Invoke-Native 'terraform' @("-chdir=$consumer", 'validate', '-no-color') | Out-Null
  $tests = Invoke-Native 'terraform' @("-chdir=$producer", 'test', '-test-directory=tests', '-no-color')
  if ($tests.Text -notmatch 'Success! 7 passed, 0 failed') { throw 'Canonical test result/count differs.' }
  Write-Host '[unit] both roots fmt/init/validate; 7/7 Terraform 1.6 normal runs passed.'
  if ($UnitOnly) { Write-Host 'PASS challenge-45 UnitOnly'; return }

  if ($null -eq (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI is required.' }
  $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get
  foreach ($service in @('s3', 'sts')) { if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." } }
  $env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $env:AWS_EC2_METADATA_DISABLED = 'true'
  Invoke-Aws @('s3api', 'create-bucket', '--bucket', $stateBucket) | Out-Null
  $stateCreated = $true

  $legacyBackend = Join-Path $scratch 'legacy.backend.hcl'; Write-Backend $legacyBackend $stateBucket $legacyKey
  Invoke-Native 'terraform' @("-chdir=$producer", 'init', '-reconfigure', '-input=false', '-no-color', "-backend-config=$legacyBackend") | Out-Null
  $producerInitialized = $true
  $producerV1 = Join-Path $scratch 'producer-v1.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$producer", 'plan', "-out=$producerV1") + $v1Producer) | Out-Null
  Assert-Plan $producer $producerV1 @{ 'aws_s3_bucket.artifacts' = 'create'; 'aws_s3_object.release["api"]' = 'create'; 'aws_s3_object.release["worker"]' = 'create' } 'Producer V1 plan'
  Invoke-Native 'terraform' @("-chdir=$producer", 'apply', '-input=false', '-no-color', $producerV1) | Out-Null
  $stateBefore = (Invoke-Native 'terraform' @("-chdir=$producer", 'state', 'list')).Text

  $canonicalBackend = Join-Path $scratch 'producer.backend.hcl'; Write-Backend $canonicalBackend $stateBucket $producerKey
  Invoke-Native 'terraform' @("-chdir=$producer", 'init', '-migrate-state', '-force-copy', '-input=false', '-no-color', "-backend-config=$canonicalBackend") | Out-Null
  $stateAfter = (Invoke-Native 'terraform' @("-chdir=$producer", 'state', 'list')).Text
  if ($stateBefore -cne $stateAfter) { throw 'Backend migration changed producer state addresses.' }
  Invoke-Aws @('s3api', 'head-object', '--bucket', $stateBucket, '--key', $producerKey) | Out-Null

  $reorder = Invoke-Native 'terraform' (@("-chdir=$producer", 'plan', '-detailed-exitcode') + $v1Reordered) @(0, 2)
  if ($reorder.ExitCode -ne 0) { throw 'V1 payload map reorder changed the producer graph.' }

  $consumerBackend = Join-Path $scratch 'consumer.backend.hcl'; Write-Backend $consumerBackend $stateBucket $consumerKey
  Invoke-Native 'terraform' @("-chdir=$consumer", 'init', '-reconfigure', '-input=false', '-no-color', "-backend-config=$consumerBackend") | Out-Null
  $consumerInitialized = $true
  $consumerV1 = Join-Path $scratch 'consumer-v1.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$consumer", 'plan', "-out=$consumerV1") + $v1Consumer) | Out-Null
  Assert-Plan $consumer $consumerV1 @{ 'aws_s3_bucket.receipts' = 'create'; 'aws_s3_object.receipt["api"]' = 'create'; 'aws_s3_object.receipt["worker"]' = 'create' } 'Consumer V1 plan'
  Invoke-Native 'terraform' @("-chdir=$consumer", 'apply', '-input=false', '-no-color', $consumerV1) | Out-Null

  $producerV2 = Join-Path $scratch 'producer-v2.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$producer", 'plan', "-out=$producerV2") + $v2Producer) | Out-Null
  Assert-Plan $producer $producerV2 @{ 'aws_s3_object.release["api"]' = 'update'; 'aws_s3_object.release["worker"]' = 'update' } 'Producer V2 plan'
  Invoke-Native 'terraform' @("-chdir=$producer", 'apply', '-input=false', '-no-color', $producerV2) | Out-Null

  $consumerV2 = Join-Path $scratch 'consumer-v2.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$consumer", 'plan', "-out=$consumerV2") + $v2Consumer) | Out-Null
  Assert-Plan $consumer $consumerV2 @{ 'aws_s3_object.receipt["api"]' = 'update'; 'aws_s3_object.receipt["worker"]' = 'update' } 'Consumer V2 plan'
  Invoke-Native 'terraform' @("-chdir=$consumer", 'apply', '-input=false', '-no-color', $consumerV2) | Out-Null

  $receiptPath = Join-Path $scratch 'api-receipt.json'
  Invoke-Aws @('s3api', 'get-object', '--bucket', "tfpro-c45-receipts-$runId", '--key', 'receipts/api.json', $receiptPath) | Out-Null
  $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
  $expectedDigest = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes('api payload v2'))).Replace('-', '').ToLowerInvariant()
  if ($receipt.artifact -cne 'api' -or $receipt.release_version -cne 'v2' -or $receipt.source_bucket -cne "tfpro-c45-artifacts-$runId" -or $receipt.source_key -cne 'releases/api.txt' -or $receipt.source_sha256 -cne $expectedDigest) { throw 'Consumer did not materialize the V2 remote-state contract.' }

  $driftBody = Join-Path $scratch 'drift.json'; [IO.File]::WriteAllText($driftBody, '{"drift":true}', [Text.UTF8Encoding]::new($false))
  Invoke-Aws @('s3api', 'put-object', '--bucket', "tfpro-c45-receipts-$runId", '--key', 'receipts/api.json', '--body', $driftBody) | Out-Null
  $repair = Join-Path $scratch 'repair.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$consumer", 'plan', "-out=$repair") + $v2Consumer) | Out-Null
  Assert-Plan $consumer $repair @{ 'aws_s3_object.receipt["api"]' = 'update' } 'Receipt drift repair'
  Invoke-Native 'terraform' @("-chdir=$consumer", 'apply', '-input=false', '-no-color', $repair) | Out-Null

  $producerClean = Invoke-Native 'terraform' (@("-chdir=$producer", 'plan', '-detailed-exitcode') + $v2Producer) @(0, 2)
  $consumerClean = Invoke-Native 'terraform' (@("-chdir=$consumer", 'plan', '-detailed-exitcode') + $v2Consumer) @(0, 2)
  if ($producerClean.ExitCode -ne 0 -or $consumerClean.ExitCode -ne 0) { throw 'Final plans are not clean.' }

  $consumerDestroy = Join-Path $scratch 'consumer-destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$consumer", 'plan', '-destroy', "-out=$consumerDestroy") + $v2Consumer) | Out-Null
  Assert-Plan $consumer $consumerDestroy @{ 'aws_s3_bucket.receipts' = 'delete'; 'aws_s3_object.receipt["api"]' = 'delete'; 'aws_s3_object.receipt["worker"]' = 'delete' } 'Consumer destroy'
  Invoke-Native 'terraform' @("-chdir=$consumer", 'apply', '-input=false', '-no-color', $consumerDestroy) | Out-Null
  $consumerInitialized = $false

  $producerDestroy = Join-Path $scratch 'producer-destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$producer", 'plan', '-destroy', "-out=$producerDestroy") + $v2Producer) | Out-Null
  Assert-Plan $producer $producerDestroy @{ 'aws_s3_bucket.artifacts' = 'delete'; 'aws_s3_object.release["api"]' = 'delete'; 'aws_s3_object.release["worker"]' = 'delete' } 'Producer destroy'
  Invoke-Native 'terraform' @("-chdir=$producer", 'apply', '-input=false', '-no-color', $producerDestroy) | Out-Null
  $producerInitialized = $false

  Invoke-Aws @('s3', 'rm', "s3://$stateBucket", '--recursive') | Out-Null
  Invoke-Aws @('s3api', 'delete-bucket', '--bucket', $stateBucket) | Out-Null
  $stateCreated = $false
  $buckets = (Invoke-Aws @('s3api', 'list-buckets', '--output', 'json')).Text | ConvertFrom-Json
  $names = @("tfpro-c45-artifacts-$runId", "tfpro-c45-receipts-$runId", $stateBucket)
  if (@($buckets.Buckets | Where-Object { $_.Name -in $names }).Count -ne 0) { throw 'S3 workload or state residue remains.' }
  Write-Host 'PASS challenge-45: 7/7 tests, S3 state migration, remote V2 contract, reorder, receipt drift repair, reverse saved destroy, zero residue.'
}
finally {
  if ($consumerInitialized -and (Test-Path $consumer)) { try { Invoke-Native 'terraform' (@("-chdir=$consumer", 'destroy', '-auto-approve') + $v2Consumer) @(0, 1) | Out-Null } catch {} }
  if ($producerInitialized -and (Test-Path $producer)) { try { Invoke-Native 'terraform' (@("-chdir=$producer", 'destroy', '-auto-approve') + $v2Producer) @(0, 1) | Out-Null } catch {} }
  if ($stateCreated) { try { Invoke-Aws @('s3', 'rm', "s3://$stateBucket", '--recursive') @(0, 1, 255) | Out-Null; Invoke-Aws @('s3api', 'delete-bucket', '--bucket', $stateBucket) @(0, 255) | Out-Null } catch {} }
  foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
  if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
