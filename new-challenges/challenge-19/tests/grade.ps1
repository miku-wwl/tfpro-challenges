[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "../starter"),
  [string]$LocalStackEndpoint = "http://localhost:4566"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$challengeRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$candidatePath = (Resolve-Path $Candidate).Path
$script:checks = 0
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("tfpro-c19-" + [guid]::NewGuid().ToString("N"))
$namePrefix = "tfpro-c19-" + ([guid]::NewGuid().ToString("N").Substring(0, 8))
$bucketName = "$namePrefix-archive"
$tableName = "$namePrefix-locks"
$statefulDirectory = $null

function Assert-LoopbackEndpoint {
  param([string]$Endpoint)
  $uri = $null
  if (-not [uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri)) {
    throw "LocalStackEndpoint must be an absolute URI"
  }
  $endpointHost = $uri.Host.Trim('[', ']').ToLowerInvariant()
  if ($uri.Scheme -notin @("http", "https") -or
    $endpointHost -notin @("localhost", "127.0.0.1", "::1") -or
    -not [string]::IsNullOrEmpty($uri.UserInfo) -or
    $uri.AbsolutePath -ne "/" -or
    -not [string]::IsNullOrEmpty($uri.Query) -or
    -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw "LocalStackEndpoint must be an HTTP(S) loopback root URL without userinfo, path, query, or fragment"
  }
}

function Remove-HclComments {
  param([string]$Text)
  $builder = [Text.StringBuilder]::new()
  $inString = $false
  $inLineComment = $false
  $inBlockComment = $false
  $escaped = $false
  for ($index = 0; $index -lt $Text.Length; $index++) {
    $character = $Text[$index]
    $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }
    if ($inLineComment) {
      if ($character -eq "`n" -or $character -eq "`r") {
        $inLineComment = $false
        [void]$builder.Append($character)
      }
      continue
    }
    if ($inBlockComment) {
      if ($character -eq '*' -and $next -eq '/') {
        $inBlockComment = $false
        $index++
      }
      elseif ($character -eq "`n" -or $character -eq "`r") {
        [void]$builder.Append($character)
      }
      continue
    }
    if ($inString) {
      [void]$builder.Append($character)
      if ($escaped) { $escaped = $false }
      elseif ($character -eq [char]92) { $escaped = $true }
      elseif ($character -eq '"') { $inString = $false }
      continue
    }
    if ($character -eq '"') {
      $inString = $true
      [void]$builder.Append($character)
    }
    elseif ($character -eq '#') { $inLineComment = $true }
    elseif ($character -eq '/' -and $next -eq '/') {
      $inLineComment = $true
      $index++
    }
    elseif ($character -eq '/' -and $next -eq '*') {
      $inBlockComment = $true
      $index++
    }
    else { [void]$builder.Append($character) }
  }
  return $builder.ToString()
}

function Get-TopLevelAwsProviderBlocks {
  param([string]$Text)
  $blocks = @()
  $headers = [regex]::Matches($Text, '(?m)^[ \t]*provider[ \t]+"aws"[ \t]*\{')
  foreach ($header in $headers) {
    $openBrace = $header.Index + $header.Value.LastIndexOf('{')
    $depth = 0
    $inString = $false
    $escaped = $false
    $closed = $false
    for ($index = $openBrace; $index -lt $Text.Length; $index++) {
      $character = $Text[$index]
      if ($inString) {
        if ($escaped) { $escaped = $false }
        elseif ($character -eq [char]92) { $escaped = $true }
        elseif ($character -eq '"') { $inString = $false }
        continue
      }
      if ($character -eq '"') { $inString = $true }
      elseif ($character -eq '{') { $depth++ }
      elseif ($character -eq '}') {
        $depth--
        if ($depth -eq 0) {
          $blocks += $Text.Substring($header.Index, $index - $header.Index + 1)
          $closed = $true
          break
        }
      }
    }
    if (-not $closed) { throw "Unclosed AWS provider block" }
  }
  return $blocks
}

function Assert-AwsProviderContract {
  param([string]$Configuration)
  $safeConfiguration = Remove-HclComments $Configuration
  $providers = @(Get-TopLevelAwsProviderBlocks $safeConfiguration)
  if ($providers.Count -ne 1) { throw "Candidate must contain exactly one top-level AWS provider block" }
  $provider = $providers[0]
  $requiredAssignments = @{
    access_key                  = '"test"'
    secret_key                  = '"test"'
    region                      = 'var\.aws_region'
    skip_credentials_validation = 'true'
    skip_metadata_api_check     = 'true'
    skip_requesting_account_id  = 'true'
    s3_use_path_style           = 'true'
    dynamodb                    = 'var\.localstack_endpoint'
    s3                          = 'var\.localstack_endpoint'
    sts                         = 'var\.localstack_endpoint'
  }
  foreach ($name in $requiredAssignments.Keys) {
    $pattern = '(?m)^\s*' + [regex]::Escape($name) + '\s*=\s*' + $requiredAssignments[$name] + '\s*$'
    if ([regex]::Matches($provider, $pattern).Count -ne 1) {
      throw "AWS provider must set $name exactly; credentials must be literal test/test and endpoints must use var.localstack_endpoint"
    }
  }
  return $safeConfiguration
}

Assert-LoopbackEndpoint $LocalStackEndpoint

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
  foreach ($service in @("s3", "dynamodb", "sts")) {
    $property = $health.services.PSObject.Properties[$service]
    Assert-True ($null -ne $property -and $property.Value -in @("available", "running")) "LocalStack $service service is healthy"
  }
}

function Assert-CandidateContract {
  $files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File -Filter "*.tf")
  Assert-True ($files.Count -gt 0) "candidate contains Terraform configuration"
  $configuration = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
  $safeConfiguration = Assert-AwsProviderContract $configuration
  Assert-True ($safeConfiguration -match 'localhost.*127') "endpoint validation restricts access to loopback"
  Assert-True ($safeConfiguration -notmatch 'import\s*\{[^}]*for_each' -and $safeConfiguration -match 'to\s*=\s*aws_s3_bucket\.archive' -and $safeConfiguration -match 'id\s*=\s*local\.bucket_name' -and $safeConfiguration -match 'to\s*=\s*aws_dynamodb_table\.locks' -and $safeConfiguration -match 'id\s*=\s*local\.table_name') "two static Terraform 1.6-compatible imports adopt both existing resources"
  Assert-True ($safeConfiguration -match 'from\s*=\s*aws_s3_object\.release_manifest_legacy' -and $safeConfiguration -match 'to\s*=\s*aws_s3_object\.release_manifest') "legacy S3 object address has a moved block"
  Assert-True ($safeConfiguration -match 'from\s*=\s*terraform_data\.inventory_legacy' -and $safeConfiguration -match 'to\s*=\s*terraform_data\.inventory') "legacy inventory address has a moved block"
  Assert-True ($safeConfiguration -match 'force_destroy\s*=\s*true') "adopted bucket can remove the deliberately unmanaged retired object"
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
  Assert-True ($testOutput -match '(?m)^Success! 1 passed, 0 failed\.$') "canonical mock test reports exactly 1/1 passed"

  $bootstrapDirectory = Join-Path $tempRoot "bootstrap"
  Copy-Item (Join-Path $tempRoot "fixtures/bootstrap") $bootstrapDirectory -Recurse -Force
  Invoke-Terraform $bootstrapDirectory @("init", "-backend=false", "-input=false")
  Invoke-Terraform $bootstrapDirectory @("apply", "-auto-approve", "-input=false", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  Assert-True $true "unmanaged S3 bucket and DynamoDB table are bootstrapped"

  $statefulDirectory = Join-Path $tempRoot "stateful"
  New-Item -ItemType Directory -Path $statefulDirectory | Out-Null
  Copy-Item (Join-Path $tempRoot "fixtures/legacy/*") $statefulDirectory -Recurse -Force
  Invoke-Terraform $statefulDirectory @("init", "-backend=false", "-input=false")
  Invoke-Terraform $statefulDirectory @("apply", "-auto-approve", "-input=false", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  Assert-True $true "legacy state and retired object are created"

  Invoke-Terraform $statefulDirectory @("state", "rm", "aws_s3_object.retired_notice")
  $stateAfterRm = (& terraform "-chdir=$statefulDirectory" state list) -join "`n"
  Assert-True ($stateAfterRm -notmatch "retired_notice") "retired object is forgotten with state rm"

  Get-ChildItem -LiteralPath $statefulDirectory -File -Filter "*.tf" | Remove-Item -Force
  Copy-Item (Join-Path $candidatePath "*") $statefulDirectory -Recurse -Force
  Invoke-Terraform $statefulDirectory @("init", "-backend=false", "-input=false")
  Invoke-Terraform $statefulDirectory @("plan", "-input=false", "-out=adopt.tfplan", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  $adoptPlan = Read-PlanJson $statefulDirectory "adopt.tfplan"
  $destructive = @($adoptPlan.resource_changes | Where-Object { $_.change.actions -contains "delete" })
  Assert-True ($destructive.Count -eq 0) "adoption and moved-address plan contains no delete or replacement"
  Invoke-Terraform $statefulDirectory @("apply", "-auto-approve", "-input=false", "adopt.tfplan")

  $canonicalState = @(& terraform "-chdir=$statefulDirectory" state list)
  foreach ($address in @("aws_s3_bucket.archive", "aws_dynamodb_table.locks", "aws_s3_object.release_manifest", "terraform_data.inventory")) {
    Assert-True ($canonicalState -contains $address) "state contains canonical address $address"
  }
  Assert-True (-not ($canonicalState -match "legacy|retired_notice")) "state contains no legacy or retired address"

  $cleanExit = Invoke-DetailedPlan $statefulDirectory @("plan", "-detailed-exitcode", "-input=false", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  Assert-True ($cleanExit -eq 0) "post-adoption plan is clean"

  $driftFile = Join-Path $tempRoot "fixtures/drift-manifest.json"
  & aws --endpoint-url $LocalStackEndpoint s3api put-object --bucket $bucketName --key "releases/manifest.json" --body $driftFile --content-type "application/json" --no-cli-pager | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "failed to inject object drift" }

  Invoke-Terraform $statefulDirectory @("plan", "-refresh-only", "-input=false", "-out=refresh.tfplan", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  $refreshPlan = Read-PlanJson $statefulDirectory "refresh.tfplan"
  $refreshChange = @($refreshPlan.resource_drift | Where-Object { $_.address -eq "aws_s3_object.release_manifest" -and $_.change.actions -contains "update" })
  Assert-True ($refreshChange.Count -eq 1) "refresh-only plan records the out-of-band manifest drift"
  Invoke-Terraform $statefulDirectory @("apply", "-auto-approve", "-input=false", "refresh.tfplan")

  Invoke-Terraform $statefulDirectory @("plan", "-input=false", "-out=repair.tfplan", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  $repairPlan = Read-PlanJson $statefulDirectory "repair.tfplan"
  $repairChange = @($repairPlan.resource_changes | Where-Object { $_.address -eq "aws_s3_object.release_manifest" -and $_.change.actions -contains "update" })
  Assert-True ($repairChange.Count -eq 1) "normal plan proposes a corrective manifest update"
  Invoke-Terraform $statefulDirectory @("apply", "-auto-approve", "-input=false", "repair.tfplan")

  $downloaded = Join-Path $tempRoot "downloaded-manifest.json"
  & aws --endpoint-url $LocalStackEndpoint s3api get-object --bucket $bucketName --key "releases/manifest.json" $downloaded --no-cli-pager | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "failed to read repaired manifest" }
  $desired = (Get-Content -Raw (Join-Path $tempRoot "fixtures/desired-manifest.json")).Trim()
  $actual = (Get-Content -Raw $downloaded).Trim()
  Assert-True ($actual -eq $desired) "corrective apply restores the desired manifest content"

  $finalCleanExit = Invoke-DetailedPlan $statefulDirectory @("plan", "-detailed-exitcode", "-input=false", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")
  Assert-True ($finalCleanExit -eq 0) "post-repair plan is clean"
  Invoke-Terraform $statefulDirectory @("destroy", "-auto-approve", "-input=false", "-var=name_prefix=$namePrefix", "-var=localstack_endpoint=$LocalStackEndpoint")

  & aws --endpoint-url $LocalStackEndpoint s3api head-bucket --bucket $bucketName --no-cli-pager 2>$null
  Assert-True ($LASTEXITCODE -ne 0) "destroy removes the adopted S3 bucket"
  & aws --endpoint-url $LocalStackEndpoint dynamodb describe-table --table-name $tableName --no-cli-pager 2>$null | Out-Null
  Assert-True ($LASTEXITCODE -ne 0) "destroy removes the adopted DynamoDB table"

  Write-Host "Challenge 19 passed: 1 canonical run plus $script:checks contract/lifecycle checks." -ForegroundColor Cyan
}
finally {
  if ($statefulDirectory -and (Test-Path (Join-Path $statefulDirectory "terraform.tfstate"))) {
    $remainingState = @(& terraform "-chdir=$statefulDirectory" state list 2>$null)
    if ($LASTEXITCODE -eq 0 -and $remainingState.Count -gt 0) {
      & terraform "-chdir=$statefulDirectory" destroy -auto-approve -input=false "-var=name_prefix=$namePrefix" "-var=localstack_endpoint=$LocalStackEndpoint" 2>$null | Out-Null
    }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccessKey
  $env:AWS_SECRET_ACCESS_KEY = $oldSecretKey
  $env:AWS_DEFAULT_REGION = $oldRegion

  # Exact, per-run names keep fallback cleanup inside this grader's ownership.
  $env:AWS_ACCESS_KEY_ID = "test"
  $env:AWS_SECRET_ACCESS_KEY = "test"
  $env:AWS_DEFAULT_REGION = "us-east-1"
  & aws --endpoint-url $LocalStackEndpoint s3 rm "s3://$bucketName" --recursive --no-cli-pager 2>$null | Out-Null
  & aws --endpoint-url $LocalStackEndpoint s3api delete-bucket --bucket $bucketName --no-cli-pager 2>$null | Out-Null
  & aws --endpoint-url $LocalStackEndpoint dynamodb delete-table --table-name $tableName --no-cli-pager 2>$null | Out-Null
  $env:AWS_ACCESS_KEY_ID = $oldAccessKey
  $env:AWS_SECRET_ACCESS_KEY = $oldSecretKey
  $env:AWS_DEFAULT_REGION = $oldRegion

  $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
  if ($resolvedTemp.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolvedTemp)) {
    Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
  }
}
