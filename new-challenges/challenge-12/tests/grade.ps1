[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot '..\starter'),
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Assert-LoopbackEndpoint([string]$Endpoint) {
  $uri = $null
  $match = [regex]::Match($Endpoint, '\Ahttp://(?:localhost|127\.0\.0\.1):(?<port>[1-9][0-9]{0,4})\z')
  if ([string]::IsNullOrEmpty($Endpoint) -or $Endpoint.IndexOf([char]13) -ge 0 -or $Endpoint.IndexOf([char]10) -ge 0 -or
      -not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or
      -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
      $uri.DnsSafeHost -notin @('localhost', '127.0.0.1') -or $uri.PathAndQuery -ne '/' -or
      -not [string]::IsNullOrEmpty($uri.UserInfo)) {
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

function Assert-Plan([string]$Root, [string]$Plan, [string[]]$Expected, [string]$Action, [string]$Label) {
  $json = (Invoke-Native 'terraform' @("-chdir=$Root", 'show', '-json', $Plan)).Text | ConvertFrom-Json
  $changed = @($json.resource_changes | Where-Object { (@($_.change.actions) -join ',') -ne 'no-op' })
  $actual = @($changed | ForEach-Object { $_.address } | Sort-Object)
  $wanted = @($Expected | Sort-Object)
  if (($actual -join '|') -cne ($wanted -join '|')) { throw "$Label address set differs: $($actual -join ', ')." }
  foreach ($change in $changed) {
    if ((@($change.change.actions) -join ',') -cne $Action -or $change.type -notin @('aws_s3_bucket', 'aws_s3_object')) {
      throw "$Label has unexpected action/type at $($change.address)."
    }
  }
}

function Assert-Candidate([string]$Root) {
  if (@(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1').Count -ne 0) { throw 'Candidate scripts are out of scope.' }
  foreach ($name in @('producer', 'consumer')) {
    $dir = Join-Path $Root $name
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "Missing $name root." }
    $files = @(Get-ChildItem -LiteralPath $dir -File -Filter '*.tf')
    if ($files.Count -ne 5) { throw "$name must contain exactly five Terraform files." }
    $text = ($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    if ($text -match '(?i)TODO|mock_provider|override_|terraform_data|backend\s+"local"') { throw "$name contains unfinished or out-of-contract configuration." }
    if ($text -notmatch 'required_version\s*=\s*"~>\s*1\.6"' -or $text -notmatch 'version\s*=\s*"~>\s*5\.100\.0"') { throw "$name version constraints differ." }
    if ($text -notmatch 'backend\s+"s3"\s*\{\s*\}') { throw "$name must use a partial S3 backend." }
    foreach ($pattern in @('access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"', 's3\s*=\s*var\.localstack_endpoint', 'sts\s*=\s*var\.localstack_endpoint')) {
      if ($text -notmatch $pattern) { throw "$name provider contract is incomplete: $pattern" }
    }
  }
  $producer = (Get-ChildItem (Join-Path $Root 'producer') -File -Filter '*.tf' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  $consumer = (Get-ChildItem (Join-Path $Root 'consumer') -File -Filter '*.tf' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  $producerResources = @([regex]::Matches($producer, 'resource\s+"([^"]+)"\s+"([^"]+)"') | ForEach-Object { "$($_.Groups[1].Value).$($_.Groups[2].Value)" } | Sort-Object)
  $consumerResources = @([regex]::Matches($consumer, 'resource\s+"([^"]+)"\s+"([^"]+)"') | ForEach-Object { "$($_.Groups[1].Value).$($_.Groups[2].Value)" } | Sort-Object)
  if (($producerResources -join '|') -cne 'aws_s3_bucket.release|aws_s3_object.service') { throw 'Producer resource set is not exact.' }
  if (($consumerResources -join '|') -cne 'aws_s3_bucket.receipts|aws_s3_object.receipt') { throw 'Consumer resource set is not exact.' }
  if ($consumer -notmatch 'data\s+"terraform_remote_state"\s+"producer"' -or $consumer -notmatch 'backend\s*=\s*"s3"' -or
      $consumer -notmatch 'endpoints\s*=\s*\{\s*s3\s*=\s*var\.localstack_endpoint' -or $consumer -notmatch 'use_path_style\s*=\s*true') {
    throw 'Consumer must use the isolated LocalStack S3 remote-state contract.'
  }
}

Assert-LoopbackEndpoint $LocalstackEndpoint
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw 'terraform is required.' }

$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
$lab = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Assert-Candidate $candidateRoot
$testText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'producer.tftest.hcl') -Raw
if ($testText -match 'mock_provider|override_' -or [regex]::Matches($testText, '(?m)^run\s+"').Count -ne 5) { throw 'Canonical suite must have exactly five Terraform 1.6 runs.' }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c12-' + [guid]::NewGuid().ToString('N'))
$candidateWork = Join-Path $scratch 'candidate'
$fixtures = Join-Path $scratch 'fixtures'
$producer = Join-Path $candidateWork 'producer'
$consumer = Join-Path $candidateWork 'consumer'
$suffix = [guid]::NewGuid().ToString('N').Substring(0, 10)
$prefix = "c12-$suffix"
$stateBucket = "tfpro-c12-state-$suffix"
$producerLegacyKey = 'legacy/producer.tfstate'
$producerKey = 'central/producer.tfstate'
$consumerKey = 'central/consumer.tfstate'
$baseProducer = @('-input=false', "-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint")
$baseConsumer = @('-input=false', "-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=state_bucket=$stateBucket", "-var=producer_state_key=$producerKey")
$producerInitialized = $false
$consumerInitialized = $false
$stateCreated = $false
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED')) { $envBefore[$name] = [Environment]::GetEnvironmentVariable($name) }

try {
  Copy-Clean $candidateRoot $candidateWork
  Copy-Clean (Join-Path $lab 'fixtures') $fixtures
  New-Item -ItemType Directory -Path (Join-Path $producer 'tests') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'producer.tftest.hcl') -Destination (Join-Path $producer 'tests\producer.tftest.hcl')
  Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $candidateWork) | Out-Null
  Invoke-Native 'terraform' @("-chdir=$producer", 'init', '-backend=false', '-input=false') | Out-Null
  Invoke-Native 'terraform' @("-chdir=$consumer", 'init', '-backend=false', '-input=false') | Out-Null
  Invoke-Native 'terraform' @("-chdir=$producer", 'validate', '-no-color') | Out-Null
  Invoke-Native 'terraform' @("-chdir=$consumer", 'validate', '-no-color') | Out-Null
  $test = Invoke-Native 'terraform' @("-chdir=$producer", 'test', '-test-directory=tests', '-no-color')
  if ($test.Text -notmatch 'Success! 5 passed, 0 failed') { throw 'Canonical run count/result mismatch.' }
  Write-Host '[unit] both roots fmt/init/validate; 5 Terraform 1.6 runs passed.'
  if ($UnitOnly) { Write-Host 'PASS challenge-12 UnitOnly'; return }

  if ($null -eq (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI is required.' }
  $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get
  foreach ($service in @('s3', 'sts')) { if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." } }
  $env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $env:AWS_EC2_METADATA_DISABLED = 'true'
  Invoke-Aws @('s3api', 'create-bucket', '--bucket', $stateBucket) | Out-Null
  $stateCreated = $true

  $legacyBackend = Join-Path $scratch 'legacy.backend.hcl'; Write-Backend $legacyBackend $stateBucket $producerLegacyKey
  Invoke-Native 'terraform' @("-chdir=$producer", 'init', '-reconfigure', '-input=false', "-backend-config=$legacyBackend") | Out-Null
  $producerInitialized = $true
  $initialProducer = Join-Path $scratch 'producer-initial.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$producer", 'plan', "-out=$initialProducer") + $baseProducer) | Out-Null
  Assert-Plan $producer $initialProducer @('aws_s3_bucket.release', 'aws_s3_object.service["catalog"]', 'aws_s3_object.service["payments"]') 'create' 'Initial producer plan'
  Invoke-Native 'terraform' @("-chdir=$producer", 'apply', '-input=false', $initialProducer) | Out-Null
  $before = (Invoke-Native 'terraform' @("-chdir=$producer", 'state', 'list')).Text

  $centralBackend = Join-Path $scratch 'producer.backend.hcl'; Write-Backend $centralBackend $stateBucket $producerKey
  Invoke-Native 'terraform' @("-chdir=$producer", 'init', '-migrate-state', '-force-copy', '-input=false', "-backend-config=$centralBackend") | Out-Null
  $after = (Invoke-Native 'terraform' @("-chdir=$producer", 'state', 'list')).Text
  if ($before -cne $after) { throw 'Backend migration changed producer state addresses.' }
  Invoke-Aws @('s3api', 'head-object', '--bucket', $stateBucket, '--key', $producerKey) | Out-Null

  $consumerBackend = Join-Path $scratch 'consumer.backend.hcl'; Write-Backend $consumerBackend $stateBucket $consumerKey
  Invoke-Native 'terraform' @("-chdir=$consumer", 'init', '-reconfigure', '-input=false', "-backend-config=$consumerBackend") | Out-Null
  $consumerInitialized = $true
  $initialConsumer = Join-Path $scratch 'consumer-initial.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$consumer", 'plan', "-out=$initialConsumer") + $baseConsumer) | Out-Null
  Assert-Plan $consumer $initialConsumer @('aws_s3_bucket.receipts', 'aws_s3_object.receipt["catalog"]', 'aws_s3_object.receipt["payments"]') 'create' 'Initial consumer plan'
  Invoke-Native 'terraform' @("-chdir=$consumer", 'apply', '-input=false', $initialConsumer) | Out-Null

  $updated = Join-Path $fixtures 'services-updated.csv'
  $producerUpdate = Join-Path $scratch 'producer-update.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$producer", 'plan', "-out=$producerUpdate") + $baseProducer + @("-var=services_file=$updated")) | Out-Null
  Assert-Plan $producer $producerUpdate @('aws_s3_object.service["orders"]') 'create' 'Producer contract update'
  Invoke-Native 'terraform' @("-chdir=$producer", 'apply', '-input=false', $producerUpdate) | Out-Null

  $consumerUpdate = Join-Path $scratch 'consumer-update.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$consumer", 'plan', "-out=$consumerUpdate") + $baseConsumer) | Out-Null
  Assert-Plan $consumer $consumerUpdate @('aws_s3_object.receipt["orders"]') 'create' 'Consumer contract update'
  Invoke-Native 'terraform' @("-chdir=$consumer", 'apply', '-input=false', $consumerUpdate) | Out-Null
  $receipt = Join-Path $scratch 'orders.json'
  Invoke-Aws @('s3api', 'get-object', '--bucket', "$prefix-consumer", '--key', 'receipts/orders.json', $receipt) | Out-Null
  $receiptJson = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
  if ($receiptJson.service -cne 'orders' -or $receiptJson.source_bucket -cne "$prefix-producer" -or $receiptJson.source_key -cne 'services/orders.json') { throw 'Consumer did not materialize the remote-state contract.' }

  $producerClean = Invoke-Native 'terraform' (@("-chdir=$producer", 'plan', '-detailed-exitcode') + $baseProducer + @("-var=services_file=$updated")) @(0, 2)
  $consumerClean = Invoke-Native 'terraform' (@("-chdir=$consumer", 'plan', '-detailed-exitcode') + $baseConsumer) @(0, 2)
  if ($producerClean.ExitCode -ne 0 -or $consumerClean.ExitCode -ne 0) { throw 'Final plans are not clean.' }

  $consumerDestroy = Join-Path $scratch 'consumer-destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$consumer", 'plan', '-destroy', "-out=$consumerDestroy") + $baseConsumer) | Out-Null
  Assert-Plan $consumer $consumerDestroy @('aws_s3_bucket.receipts', 'aws_s3_object.receipt["catalog"]', 'aws_s3_object.receipt["orders"]', 'aws_s3_object.receipt["payments"]') 'delete' 'Consumer destroy'
  Invoke-Native 'terraform' @("-chdir=$consumer", 'apply', '-input=false', $consumerDestroy) | Out-Null
  $consumerInitialized = $false

  $producerDestroy = Join-Path $scratch 'producer-destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$producer", 'plan', '-destroy', "-out=$producerDestroy") + $baseProducer + @("-var=services_file=$updated")) | Out-Null
  Assert-Plan $producer $producerDestroy @('aws_s3_bucket.release', 'aws_s3_object.service["catalog"]', 'aws_s3_object.service["orders"]', 'aws_s3_object.service["payments"]') 'delete' 'Producer destroy'
  Invoke-Native 'terraform' @("-chdir=$producer", 'apply', '-input=false', $producerDestroy) | Out-Null
  $producerInitialized = $false

  Invoke-Aws @('s3', 'rm', "s3://$stateBucket", '--recursive') | Out-Null
  Invoke-Aws @('s3api', 'delete-bucket', '--bucket', $stateBucket) | Out-Null
  $stateCreated = $false
  $remaining = (Invoke-Aws @('s3api', 'list-buckets', '--query', "Buckets[?starts_with(Name, '$prefix') || Name=='$stateBucket'].Name", '--output', 'text')).Text.Trim()
  if ($remaining) { throw "S3 residue remains: $remaining" }
  Write-Host 'PASS challenge-12: 5/5 tests, S3 state migration, remote contract update, saved plans, reverse destroy, zero residue.'
}
finally {
  if ($consumerInitialized -and (Test-Path $consumer)) { try { Invoke-Native 'terraform' (@("-chdir=$consumer", 'destroy', '-auto-approve') + $baseConsumer) @(0, 1) | Out-Null } catch {} }
  if ($producerInitialized -and (Test-Path $producer)) { try { Invoke-Native 'terraform' (@("-chdir=$producer", 'destroy', '-auto-approve') + $baseProducer + @("-var=services_file=$(Join-Path $fixtures 'services-updated.csv')")) @(0, 1) | Out-Null } catch {} }
  if ($stateCreated) { try { Invoke-Aws @('s3', 'rm', "s3://$stateBucket", '--recursive') @(0, 1, 255) | Out-Null; Invoke-Aws @('s3api', 'delete-bucket', '--bucket', $stateBucket) @(0, 255) | Out-Null } catch {} }
  foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
  if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
