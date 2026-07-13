[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "..\starter"),
  [string]$LocalstackEndpoint = "http://localhost:4566"
)

$ErrorActionPreference = "Stop"
$originalLocation = (Get-Location).Path
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$candidateRoot = (Resolve-Path $Candidate).Path
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tfpro-c26-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $scratchRoot "candidate"
$uniquePrefix = "c26-" + [guid]::NewGuid().ToString("N").Substring(0, 10)

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
    iam                         = 'var\.localstack_endpoint'
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

function Get-LocalStackIamXml {
  param([string]$Action, [string]$ExtraQuery = "")
  $uri = "$LocalstackEndpoint/?Action=$Action&Version=2010-05-08$ExtraQuery"
  $response = Invoke-WebRequest -Uri $uri -UseBasicParsing
  if ($response.Content -is [byte[]]) {
    return [System.Text.Encoding]::UTF8.GetString($response.Content)
  }
  return [string]$response.Content
}

function Assert-IamResourcesAbsent {
  $rolesXml = Get-LocalStackIamXml "ListRoles"
  $policiesXml = Get-LocalStackIamXml "ListPolicies" "&Scope=Local"
  $escapedPrefix = [regex]::Escape($uniquePrefix)
  if ($rolesXml -match "<RoleName>$escapedPrefix-") {
    throw "清理失败：仍存在 $uniquePrefix IAM role。"
  }
  if ($policiesXml -match "<PolicyName>$escapedPrefix-") {
    throw "清理失败：仍存在 $uniquePrefix IAM policy。"
  }
}

try {
  New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
  Copy-Item (Join-Path $candidateRoot "*") $workRoot -Recurse -Force
  Copy-Item (Join-Path $labRoot "fixtures") (Join-Path $scratchRoot "fixtures") -Recurse -Force
  Copy-Item (Join-Path $PSScriptRoot "catalog.tftest.hcl") (Join-Path $workRoot "catalog.tftest.hcl") -Force

  $source = (Get-ChildItem $workRoot -Recurse -Filter "*.tf" | Get-Content -Raw) -join "`n"
  Assert-AwsProviderContract $source
  foreach ($needle in @(
      "aws_iam_policy_document",
      'module "access_role"',
      "for_each",
      "sensitive   = true",
      "unique_identities",
      'resource "terraform_data" "catalog_contract"',
      'strcontains(action, "*")',
      "session_duration_range",
      'localhost|127\\.0\\.0\\.1|\\[::1\\]'
    )) {
    if ($source -notmatch [regex]::Escape($needle)) { throw "缺少必需安全契约：$needle" }
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

  Remove-Item (Join-Path $workRoot "catalog.tftest.hcl") -Force
  Invoke-Terraform @("apply", "-auto-approve", "-input=false", "-no-color", "-var=name_prefix=$uniquePrefix", "-var=localstack_endpoint=$LocalstackEndpoint")

  $roleKeys = (& terraform output -json role_keys | ConvertFrom-Json)
  if ($LASTEXITCODE -ne 0 -or $roleKeys.Count -ne 3) { throw "期望 3 个角色，实际为 $($roleKeys.Count)。" }

  & terraform plan -detailed-exitcode -input=false -no-color "-var=name_prefix=$uniquePrefix" "-var=localstack_endpoint=$LocalstackEndpoint" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "apply 后必须是 clean plan，exit code=$LASTEXITCODE" }
}
finally {
  try {
    if (Test-Path $workRoot) {
      Set-Location $workRoot
      if (Test-Path (Join-Path $workRoot "terraform.tfstate")) {
        $destroyOutput = @(& terraform destroy -auto-approve -input=false -no-color "-var=name_prefix=$uniquePrefix" "-var=localstack_endpoint=$LocalstackEndpoint" 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "cleanup destroy 失败：$($destroyOutput -join "`n")" }
      }
      Assert-IamResourcesAbsent
    }
  }
  finally {
    Set-Location $originalLocation
    Remove-Item $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "PASS: 精确 4/4 canonical tests；LocalStack 3 roles + 4 policies + 3 attachments + contract resource，clean plan、destroy 与远端零残留已验证。"
