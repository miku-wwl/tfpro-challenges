[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "../starter"),
  [string]$LocalStackEndpoint = "http://localhost:4566"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

function Assert-StrictLoopbackEndpoint {
  param([string]$Endpoint)
  if ([string]::IsNullOrWhiteSpace($Endpoint) -or
    $Endpoint -ne $Endpoint.Trim() -or
    $Endpoint -notmatch '^(?i:https?)://(?i:localhost|127\.0\.0\.1|\[::1\])(?::[0-9]{1,5})?/?$') {
    throw "LocalStackEndpoint must be a plain loopback HTTP(S) origin without userinfo, path, query, or fragment"
  }
  try { $uri = [Uri]$Endpoint }
  catch { throw "LocalStackEndpoint is not a valid absolute URI" }
  if (-not $uri.IsAbsoluteUri -or
    $uri.Scheme -notin @("http", "https") -or
    $uri.DnsSafeHost -notin @("localhost", "127.0.0.1", "::1") -or
    -not [string]::IsNullOrEmpty($uri.UserInfo) -or
    $uri.AbsolutePath -ne "/" -or
    -not [string]::IsNullOrEmpty($uri.Query) -or
    -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw "LocalStackEndpoint must be a loopback HTTP(S) origin with no userinfo, path, query, or fragment"
  }
}

function Remove-HclComments([string]$Text) {
  $builder = [Text.StringBuilder]::new($Text.Length)
  $state = "code"
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $current = $Text[$i]
    $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
    if ($state -eq "code") {
      if ($current -eq '"') { [void]$builder.Append($current); $state = "string" }
      elseif ($current -eq '#') { [void]$builder.Append(' '); $state = "line" }
      elseif ($current -eq '/' -and $next -eq '/') { [void]$builder.Append("  "); $i++; $state = "line" }
      elseif ($current -eq '/' -and $next -eq '*') { [void]$builder.Append("  "); $i++; $state = "block" }
      else { [void]$builder.Append($current) }
    }
    elseif ($state -eq "string") {
      [void]$builder.Append($current)
      if ($current -eq '\' -and $i + 1 -lt $Text.Length) { $i++; [void]$builder.Append($Text[$i]) }
      elseif ($current -eq '"') { $state = "code" }
    }
    elseif ($state -eq "line") {
      if ($current -eq "`n") { [void]$builder.Append($current); $state = "code" }
      else { [void]$builder.Append(' ') }
    }
    else {
      if ($current -eq '*' -and $next -eq '/') { [void]$builder.Append("  "); $i++; $state = "code" }
      elseif ($current -eq "`n") { [void]$builder.Append($current) }
      else { [void]$builder.Append(' ') }
    }
  }
  return $builder.ToString()
}

function Get-HclBlocks([string]$Text, [string]$HeaderPattern) {
  $blocks = [System.Collections.Generic.List[string]]::new()
  foreach ($match in [regex]::Matches($Text, $HeaderPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    $open = $Text.IndexOf('{', $match.Index)
    if ($open -lt 0) { continue }
    $depth = 0
    $inString = $false
    for ($i = $open; $i -lt $Text.Length; $i++) {
      $current = $Text[$i]
      if ($inString) {
        if ($current -eq '\') { $i++; continue }
        if ($current -eq '"') { $inString = $false }
        continue
      }
      if ($current -eq '"') { $inString = $true; continue }
      if ($current -eq '{') { $depth++ }
      elseif ($current -eq '}') {
        $depth--
        if ($depth -eq 0) {
          $blocks.Add($Text.Substring($match.Index, $i - $match.Index + 1))
          break
        }
      }
    }
  }
  return @($blocks)
}

function Test-ExactHclAssignment([string]$Block, [string]$Name, [string]$ValuePattern) {
  return [regex]::Matches($Block, "(?m)^\s*$([regex]::Escape($Name))\s*=\s*$ValuePattern\s*$").Count -eq 1
}

function Assert-AwsProviderBlocks([string]$SafeConfiguration) {
  $providerBlocks = @(Get-HclBlocks $SafeConfiguration 'provider\s+"aws"\s*\{')
  Assert-True ($providerBlocks.Count -eq 2) "candidate declares exactly two AWS provider blocks"

  $aliasedBlocks = @($providerBlocks | Where-Object { $_ -match '(?m)^\s*alias\s*=' })
  $primaryBlocks = @($providerBlocks | Where-Object { Test-ExactHclAssignment $_ "alias" '"primary"' })
  $drBlocks = @($providerBlocks | Where-Object { Test-ExactHclAssignment $_ "alias" '"dr"' })
  Assert-True ($aliasedBlocks.Count -eq 2 -and $primaryBlocks.Count -eq 1 -and $drBlocks.Count -eq 1) "providers use unique literal aliases primary and dr"

  $slots = @(
    @{ Name = "primary"; Block = $primaryBlocks[0]; Region = 'var\.primary_region' },
    @{ Name = "dr"; Block = $drBlocks[0]; Region = 'var\.dr_region' }
  )
  foreach ($slot in $slots) {
    $block = [string]$slot.Block
    $required = @{
      region                      = [string]$slot.Region
      access_key                  = '"test"'
      secret_key                  = '"test"'
      skip_credentials_validation = 'true'
      skip_metadata_api_check     = 'true'
      skip_requesting_account_id  = 'true'
      s3_use_path_style           = 'true'
    }
    foreach ($entry in $required.GetEnumerator()) {
      Assert-True (Test-ExactHclAssignment $block $entry.Key $entry.Value) "aws.$($slot.Name) fixes literal $($entry.Key) independently"
    }
    Assert-True (-not ($block -match '(?mi)^\s*(profile|token|shared_credentials_files|shared_config_files)\s*=') -and -not ($block -match '(?mi)^\s*assume_role\s*\{')) "aws.$($slot.Name) has no alternate real credential source"

    $endpointBlocks = @(Get-HclBlocks $block 'endpoints\s*\{')
    Assert-True ($endpointBlocks.Count -eq 1) "aws.$($slot.Name) has exactly one endpoints block"
    $endpointBlock = $endpointBlocks[0]
    $endpointKeys = @([regex]::Matches($endpointBlock, '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    Assert-True (($endpointKeys -join ",") -eq "s3,sns,sts") "aws.$($slot.Name) exposes only S3, SNS, and STS endpoints"
    foreach ($service in @("s3", "sns", "sts")) {
      Assert-True (Test-ExactHclAssignment $endpointBlock $service 'var\.localstack_endpoint') "aws.$($slot.Name) $service endpoint references var.localstack_endpoint"
    }
  }
}

Assert-StrictLoopbackEndpoint $LocalStackEndpoint
$LocalStackEndpoint = $LocalStackEndpoint.TrimEnd('/')

$challengeRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$candidatePath = (Resolve-Path $Candidate).Path
$script:checks = 0
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("tfpro-c20-" + [guid]::NewGuid().ToString("N"))
$namePrefix = "tfpro-c20-" + ([guid]::NewGuid().ToString("N").Substring(0, 8))
$primaryBucket = "$namePrefix-primary"
$drBucket = "$namePrefix-dr"
$primaryTopicName = "$namePrefix-primary-events"
$drTopicName = "$namePrefix-dr-events"
$statefulDirectory = $null

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
  $script:checks++
  Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Invoke-Terraform {
  param([string]$Directory, [string[]]$Arguments)
  Push-Location $Directory
  try {
    & terraform @Arguments | Out-Host
    $code = $LASTEXITCODE
  }
  finally { Pop-Location }
  if ($code -ne 0) { throw "terraform $($Arguments -join ' ') failed with exit code $code" }
}

function Invoke-TerraformCapture {
  param([string]$Directory, [string[]]$Arguments)
  Push-Location $Directory
  try {
    $lines = @(& terraform @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $code = $LASTEXITCODE
  }
  finally { Pop-Location }
  $captured = $lines -join "`n"
  Write-Host $captured
  if ($code -ne 0) { throw "terraform $($Arguments -join ' ') failed with exit code $code" }
  return $captured
}

function Invoke-DetailedPlan {
  param([string]$Directory, [string[]]$Arguments)
  Push-Location $Directory
  try {
    & terraform @Arguments | Out-Host
    $code = $LASTEXITCODE
  }
  finally { Pop-Location }
  if ($code -notin @(0, 2)) { throw "terraform plan failed with exit code $code" }
  return $code
}

function Read-PlanJson {
  param([string]$Directory, [string]$PlanFile)
  Push-Location $Directory
  try {
    $raw = (& terraform show -json $PlanFile) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "terraform show failed" }
  }
  finally { Pop-Location }
  return ($raw | ConvertFrom-Json -Depth 100)
}

function Test-LocalStackServices {
  $health = Invoke-RestMethod -Uri "$LocalStackEndpoint/_localstack/health" -TimeoutSec 5
  foreach ($service in @("s3", "sns", "sts")) {
    $property = $health.services.PSObject.Properties[$service]
    Assert-True ($null -ne $property -and $property.Value -in @("available", "running")) "LocalStack $service service is healthy"
  }
}

function Assert-CandidateContract {
  $files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File -Filter "*.tf")
  Assert-True ($files.Count -ge 10) "candidate contains root and nested-module Terraform files"
  $configuration = Remove-HclComments (($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n")
  Assert-AwsProviderBlocks $configuration
  Assert-True ($configuration -match 'aws\.target\s*=\s*aws\.primary' -and $configuration -match 'aws\.target\s*=\s*aws\.dr') "primary and DR modules receive distinct aliased providers"
  Assert-True (([regex]::Matches($configuration, 'configuration_aliases')).Count -ge 2) "both nested module boundaries declare configuration_aliases"
  foreach ($legacy in @("aws_s3_bucket.primary", "aws_sns_topic.primary_events", "aws_s3_bucket.dr", "aws_sns_topic.dr_events")) {
    Assert-True ($configuration -match [regex]::Escape("from = $legacy")) "moved block covers $legacy"
  }
  Assert-True ($configuration -match 'to\s*=\s*module\.primary\.module\.storage\.aws_s3_bucket\.this' -and $configuration -match 'to\s*=\s*module\.dr\.module\.storage\.aws_s3_bucket\.this') "bucket state lands at two-level nested addresses"
}

function Get-TopicArns {
  param([string]$Region)
  $raw = (& aws --endpoint-url $LocalStackEndpoint --region $Region sns list-topics --output json --no-cli-pager) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "failed to list SNS topics in $Region" }
  return @((($raw | ConvertFrom-Json).Topics | ForEach-Object TopicArn))
}

New-Item -ItemType Directory -Path $tempRoot | Out-Null
$oldAccessKey = $env:AWS_ACCESS_KEY_ID
$oldSecretKey = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

try {
  Assert-CandidateContract
  Test-LocalStackServices
  Copy-Item (Join-Path $challengeRoot "fixtures") (Join-Path $tempRoot "fixtures") -Recurse -Force

  $mockDirectory = Join-Path $tempRoot "mock"
  New-Item -ItemType Directory -Path $mockDirectory | Out-Null
  Copy-Item (Join-Path $candidatePath "*") $mockDirectory -Recurse -Force
  New-Item -ItemType Directory -Path (Join-Path $mockDirectory "tests") -Force | Out-Null
  Copy-Item (Join-Path $PSScriptRoot "contract.tftest.hcl") (Join-Path $mockDirectory "tests/contract.tftest.hcl") -Force
  Invoke-Terraform $mockDirectory @("init", "-backend=false", "-input=false")
  $testOutput = Invoke-TerraformCapture $mockDirectory @("test", "-no-color")
  Assert-True ($testOutput -match '(?m)^Success! 1 passed, 0 failed\.$') "canonical nested-module mock test reports exactly 1/1 passed"

  $statefulDirectory = Join-Path $tempRoot "stateful"
  New-Item -ItemType Directory -Path $statefulDirectory | Out-Null
  Copy-Item (Join-Path $tempRoot "fixtures/legacy/*") $statefulDirectory -Recurse -Force
  Invoke-Terraform $statefulDirectory @("init", "-backend=false", "-input=false")
  Invoke-Terraform $statefulDirectory @("apply", "-auto-approve", "-input=false", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  Assert-True $true "legacy flat state creates two buckets and two topics"

  Get-ChildItem -LiteralPath $statefulDirectory -File -Filter "*.tf" | Remove-Item -Force
  Copy-Item (Join-Path $candidatePath "*") $statefulDirectory -Recurse -Force
  Invoke-Terraform $statefulDirectory @("init", "-backend=false", "-input=false")
  Invoke-Terraform $statefulDirectory @("plan", "-input=false", "-out=refactor.tfplan", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  $refactorPlan = Read-PlanJson $statefulDirectory "refactor.tfplan"
  $mutating = @($refactorPlan.resource_changes | Where-Object { $_.change.actions -contains "create" -or $_.change.actions -contains "delete" })
  Assert-True ($mutating.Count -eq 0) "flat-to-nested refactor has zero create, delete, or replacement actions"
  Invoke-Terraform $statefulDirectory @("apply", "-auto-approve", "-input=false", "refactor.tfplan")

  $state = @(& terraform "-chdir=$statefulDirectory" state list)
  $expectedAddresses = @(
    "module.primary.module.storage.aws_s3_bucket.this",
    "module.primary.aws_sns_topic.events",
    "module.dr.module.storage.aws_s3_bucket.this",
    "module.dr.aws_sns_topic.events"
  )
  foreach ($address in $expectedAddresses) {
    Assert-True ($state -contains $address) "state contains refactored address $address"
  }
  Assert-True (-not ($state -match '^aws_(s3_bucket|sns_topic)\.')) "state contains no legacy root resource address"

  $outputRaw = (& terraform "-chdir=$statefulDirectory" output -json regional_contract) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "failed to read regional contract" }
  $contract = $outputRaw | ConvertFrom-Json
  Assert-True ($contract.primary.region -eq "us-east-1" -and $contract.dr.region -eq "us-west-2") "regional contract preserves distinct provider regions"
  Assert-True ($contract.primary.peer_bucket -eq $drBucket -and $contract.dr.peer_bucket -eq $primaryBucket) "cross-region peer bucket contract is symmetric"

  $cleanExit = Invoke-DetailedPlan $statefulDirectory @("plan", "-detailed-exitcode", "-input=false", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  Assert-True ($cleanExit -eq 0) "post-refactor plan is clean"

  $bucketRaw = (& aws --endpoint-url $LocalStackEndpoint s3api list-buckets --output json --no-cli-pager) -join "`n"
  $bucketNames = @(($bucketRaw | ConvertFrom-Json).Buckets | ForEach-Object Name)
  Assert-True ($bucketNames -contains $primaryBucket -and $bucketNames -contains $drBucket) "both LocalStack S3 buckets retain their identities"
  $primaryTopics = Get-TopicArns "us-east-1"
  $drTopics = Get-TopicArns "us-west-2"
  Assert-True (@($primaryTopics | Where-Object { $_ -match ":$([regex]::Escape($primaryTopicName))$" }).Count -eq 1) "primary topic exists in the primary region"
  Assert-True (@($drTopics | Where-Object { $_ -match ":$([regex]::Escape($drTopicName))$" }).Count -eq 1) "DR topic exists in the DR region"

  Invoke-Terraform $statefulDirectory @("destroy", "-auto-approve", "-input=false", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  $bucketRawAfter = (& aws --endpoint-url $LocalStackEndpoint s3api list-buckets --output json --no-cli-pager) -join "`n"
  $bucketNamesAfter = @(($bucketRawAfter | ConvertFrom-Json).Buckets | ForEach-Object Name)
  Assert-True ($bucketNamesAfter -notcontains $primaryBucket -and $bucketNamesAfter -notcontains $drBucket) "destroy removes both buckets"
  $allTopicsAfter = @((Get-TopicArns "us-east-1") + (Get-TopicArns "us-west-2"))
  Assert-True (@($allTopicsAfter | Where-Object { $_ -match ":$([regex]::Escape($namePrefix))-(primary|dr)-events$" }).Count -eq 0) "destroy removes both topics"

  Write-Host "Challenge 20 passed: 1 canonical run plus $script:checks contract/lifecycle checks." -ForegroundColor Cyan
}
finally {
  if ($statefulDirectory -and (Test-Path (Join-Path $statefulDirectory "terraform.tfstate"))) {
    $remainingState = @(& terraform "-chdir=$statefulDirectory" state list 2>$null)
    if ($LASTEXITCODE -eq 0 -and $remainingState.Count -gt 0) {
      & terraform "-chdir=$statefulDirectory" destroy -auto-approve -input=false "-var=name_prefix=$namePrefix" "-var=localstack_endpoint=$LocalStackEndpoint" 2>$null | Out-Null
    }
  }
  $env:AWS_ACCESS_KEY_ID = "test"
  $env:AWS_SECRET_ACCESS_KEY = "test"
  foreach ($bucket in @($primaryBucket, $drBucket)) {
    & aws --endpoint-url $LocalStackEndpoint s3 rm "s3://$bucket" --recursive --no-cli-pager 2>$null | Out-Null
    & aws --endpoint-url $LocalStackEndpoint s3api delete-bucket --bucket $bucket --no-cli-pager 2>$null | Out-Null
  }
  foreach ($region in @("us-east-1", "us-west-2")) {
    try {
      foreach ($arn in @(Get-TopicArns $region | Where-Object { $_ -match ":$([regex]::Escape($namePrefix))-(primary|dr)-events$" })) {
        & aws --endpoint-url $LocalStackEndpoint --region $region sns delete-topic --topic-arn $arn --no-cli-pager 2>$null | Out-Null
      }
    }
    catch { }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccessKey
  $env:AWS_SECRET_ACCESS_KEY = $oldSecretKey
  $env:AWS_DEFAULT_REGION = $oldRegion

  $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
  if ($resolvedTemp.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolvedTemp)) {
    Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
  }
}
