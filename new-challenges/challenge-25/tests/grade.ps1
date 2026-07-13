[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "..\starter"),
  [string]$LocalstackEndpoint = "http://localhost:4566"
)

$ErrorActionPreference = "Stop"
$originalLocation = (Get-Location).Path
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$candidateRoot = (Resolve-Path $Candidate).Path
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tfpro-c25-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $scratchRoot "candidate"
$prefix = "c25-" + [guid]::NewGuid().ToString("N").Substring(0, 10)
$bucket = "$prefix-dev-config"
$table = "$prefix-dev-config"

function Assert-LoopbackEndpoint {
  param([string]$Endpoint)
  $uri = $null
  if (-not [uri]::TryCreate($Endpoint, [System.UriKind]::Absolute, [ref]$uri)) {
    throw "LocalstackEndpoint 必须是绝对 URI。"
  }
  $endpointHost = $uri.Host.Trim('[', ']').ToLowerInvariant()
  if ($uri.Scheme -notin @("http", "https") -or
    $endpointHost -notin @("localhost", "127.0.0.1", "::1") -or
    -not [string]::IsNullOrEmpty($uri.UserInfo) -or
    $uri.AbsolutePath -ne "/" -or
    -not [string]::IsNullOrEmpty($uri.Query) -or
    -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw "LocalstackEndpoint 仅允许 localhost、127.0.0.1 或 ::1 的 HTTP(S) 根地址。"
  }
}

function Remove-HclComments {
  param([string]$Text)
  $builder = [System.Text.StringBuilder]::new()
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

function Assert-AwsProviderContract {
  param([string]$Source)
  $cleanSource = Remove-HclComments $Source
  $blocks = @([regex]::Matches($cleanSource, '(?ms)^provider\s+"aws"\s*\{.*?^\}'))
  if ($blocks.Count -ne 1) { throw "候选配置必须且只能包含一个顶层 AWS provider block。" }
  $block = $blocks[0].Value
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
    if ([regex]::Matches($block, $pattern).Count -ne 1) {
      throw "AWS provider 必须精确设置 $name；凭证只能是字面量 test/test，endpoint 必须来自 localstack_endpoint。"
    }
  }
}

Assert-LoopbackEndpoint $LocalstackEndpoint

function Invoke-Terraform {
  param([string[]]$Arguments)
  & terraform @Arguments
  if ($LASTEXITCODE -ne 0) { throw "terraform $($Arguments -join ' ') 失败，exit code=$LASTEXITCODE" }
}

function Convert-ResponseContentToText {
  param($Response)
  if ($Response.Content -is [byte[]]) {
    return [System.Text.Encoding]::UTF8.GetString($Response.Content)
  }
  return [string]$Response.Content
}

function Assert-S3BucketAbsent {
  param([string]$BucketName)
  try {
    Invoke-WebRequest -Uri "$LocalstackEndpoint/$BucketName" -Method Head -UseBasicParsing | Out-Null
    throw "清理失败：S3 bucket $BucketName 仍存在。"
  }
  catch {
    $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
    if ($status -ne 404) { throw }
  }
}

function Assert-DynamoDbTableAbsent {
  param([string]$TableName)
  $response = Invoke-WebRequest -Uri $LocalstackEndpoint -Method Post -UseBasicParsing -Headers @{
    "Content-Type" = "application/x-amz-json-1.0"
    "X-Amz-Target" = "DynamoDB_20120810.ListTables"
  } -Body "{}"
  $payload = Convert-ResponseContentToText $response | ConvertFrom-Json
  if (@($payload.TableNames) -contains $TableName) {
    throw "清理失败：DynamoDB table $TableName 仍存在。"
  }
}

try {
  New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
  Copy-Item (Join-Path $candidateRoot "*") $workRoot -Recurse -Force
  Copy-Item (Join-Path $labRoot "fixtures") (Join-Path $scratchRoot "fixtures") -Recurse -Force
  Copy-Item (Join-Path $PSScriptRoot "lifecycle.tftest.hcl") (Join-Path $workRoot "lifecycle.tftest.hcl") -Force

  $source = (Get-ChildItem $workRoot -Filter "*.tf" | Get-Content -Raw) -join "`n"
  Assert-AwsProviderContract $source
  foreach ($needle in @("prevent_destroy = true", "replace_triggered_by", "precondition", "postcondition", 'resource "terraform_data" "config_revision"', "aws_dynamodb_table_item")) {
    if ($source -notmatch [regex]::Escape($needle)) { throw "缺少必需实现：$needle" }
  }

  Set-Location $workRoot
  Invoke-Terraform @("fmt", "-check", "-recursive")
  Invoke-Terraform @("init", "-input=false", "-no-color")
  Invoke-Terraform @("validate", "-no-color")

  $testOutput = @(& terraform test -no-color 2>&1)
  $testExit = $LASTEXITCODE
  $testOutput | ForEach-Object { Write-Host $_ }
  $testText = $testOutput -join "`n"
  if ($testExit -ne 0) { throw "canonical tests 失败，exit code=$testExit" }
  if ([regex]::Matches($testText, '(?m)^Success! 4 passed, 0 failed\.$').Count -ne 1) {
    throw "必须精确通过 4/4 canonical tests。"
  }
  Remove-Item (Join-Path $workRoot "lifecycle.tftest.hcl") -Force

  Invoke-Terraform @("apply", "-auto-approve", "-input=false", "-no-color", "-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint")
  $bucket = (& terraform output -raw bucket_name).Trim()
  $key = (& terraform output -raw object_key).Trim()

  Invoke-Terraform @("state", "rm", "aws_s3_bucket.config")
  Invoke-Terraform @("import", "-input=false", "-no-color", "-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint", "aws_s3_bucket.config", $bucket)

  & terraform plan -detailed-exitcode -input=false -no-color "-var=name_prefix=$prefix" "-var=localstack_endpoint=$LocalstackEndpoint" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "import 后必须 clean plan，exit code=$LASTEXITCODE" }

  Invoke-WebRequest -Uri "$LocalstackEndpoint/$bucket/$key" -Method Put -Body '{"drifted":true}' -ContentType "application/json" -UseBasicParsing | Out-Null
  Invoke-Terraform @("plan", "-refresh-only", "-out=refresh.tfplan", "-input=false", "-no-color", "-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint")
  $refreshJson = & terraform show -json refresh.tfplan
  if ($LASTEXITCODE -ne 0 -or $refreshJson -notmatch 'aws_s3_object.config') { throw "refresh-only plan 未记录对象漂移。" }
  Invoke-Terraform @("apply", "-auto-approve", "-input=false", "-no-color", "refresh.tfplan")

  & terraform plan -detailed-exitcode -input=false -no-color "-out=repair.tfplan" "-var=name_prefix=$prefix" "-var=localstack_endpoint=$LocalstackEndpoint" | Out-Null
  if ($LASTEXITCODE -ne 2) { throw "记录漂移后普通 plan 应返回 2，实际=$LASTEXITCODE" }
  Invoke-Terraform @("apply", "-auto-approve", "-input=false", "-no-color", "repair.tfplan")

  & terraform plan -detailed-exitcode -input=false -no-color "-var=name_prefix=$prefix" "-var=localstack_endpoint=$LocalstackEndpoint" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "漂移恢复后必须 clean plan，exit code=$LASTEXITCODE" }

  & terraform destroy -auto-approve -input=false -no-color "-var=name_prefix=$prefix" "-var=localstack_endpoint=$LocalstackEndpoint" 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) { throw "prevent_destroy 未阻止普通 destroy。" }
}
finally {
  try {
    if (Test-Path $workRoot) {
      Set-Location $workRoot
      if (Test-Path (Join-Path $workRoot "terraform.tfstate")) {
        $addresses = @(& terraform state list 2>$null)
        if ($LASTEXITCODE -ne 0) { throw "cleanup state list 失败。" }
        if ($addresses -contains "aws_s3_bucket.config") {
          & terraform state rm aws_s3_bucket.config | Out-Null
          if ($LASTEXITCODE -ne 0) { throw "cleanup state rm bucket 失败。" }
        }
        $destroyOutput = @(& terraform destroy -auto-approve -input=false -no-color "-var=name_prefix=$prefix" "-var=localstack_endpoint=$LocalstackEndpoint" 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "cleanup destroy 失败：$($destroyOutput -join "`n")" }
      }

      try {
        Invoke-WebRequest -Uri "$LocalstackEndpoint/$bucket" -Method Delete -UseBasicParsing | Out-Null
      }
      catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        if ($status -ne 404) { throw }
      }
      Assert-S3BucketAbsent $bucket
      Assert-DynamoDbTableAbsent $table
    }
  }
  finally {
    Set-Location $originalLocation
    Remove-Item $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "PASS: 精确 4/4 canonical tests；LocalStack import/refresh-only/repair/clean-plan 通过，destroy 与远端零残留已验证。"
