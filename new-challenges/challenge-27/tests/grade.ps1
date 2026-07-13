[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "..\starter"),
  [string]$LocalstackEndpoint = "http://localhost:4566"
)

$ErrorActionPreference = "Stop"
$originalLocation = (Get-Location).Path
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$candidateRoot = (Resolve-Path $Candidate).Path
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tfpro-c27-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $scratchRoot "candidate"
$prefix = "c27-" + [guid]::NewGuid().ToString("N").Substring(0, 10)
$manifestV1 = Join-Path $scratchRoot "fixtures\release-v1.json"
$manifestV2 = Join-Path $scratchRoot "fixtures\release-v2.json"
$activeManifest = $manifestV1
$activeVersion = "1.0.0"
$bucket = "$prefix-dev-releases"

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
    s3                          = 'var\.localstack_endpoint'
    sns                         = 'var\.localstack_endpoint'
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

function Get-HttpStatus {
  param([string]$Uri)
  try {
    $response = Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing
    return [int]$response.StatusCode
  }
  catch {
    if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
    throw
  }
}

function Assert-PublishObjectsAfterUpgrade {
  $oldStatus = Get-HttpStatus "$LocalstackEndpoint/$bucket/releases/1.0.0/manifest.json"
  $newStatus = Get-HttpStatus "$LocalstackEndpoint/$bucket/releases/1.1.0/manifest.json"
  if ($oldStatus -ne 404) { throw "升级后旧 v1 manifest 应不存在，HTTP=$oldStatus。" }
  if ($newStatus -ne 200) { throw "升级后 v2 manifest 应存在，HTTP=$newStatus。" }
}

function Assert-S3BucketAbsent {
  $status = Get-HttpStatus "$LocalstackEndpoint/$bucket"
  if ($status -ne 404) { throw "清理失败：S3 bucket $bucket 仍存在，HTTP=$status。" }
}

function Assert-SnsTopicAbsent {
  $response = Invoke-WebRequest -Uri "$LocalstackEndpoint/?Action=ListTopics&Version=2010-03-31" -UseBasicParsing
  $content = if ($response.Content -is [byte[]]) {
    [System.Text.Encoding]::UTF8.GetString($response.Content)
  }
  else {
    [string]$response.Content
  }
  if ($content -match [regex]::Escape(":$prefix-dev-releases")) {
    throw "清理失败：SNS topic $prefix-dev-releases 仍存在。"
  }
}

try {
  New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
  Copy-Item (Join-Path $candidateRoot "*") $workRoot -Recurse -Force
  Copy-Item (Join-Path $labRoot "fixtures") (Join-Path $scratchRoot "fixtures") -Recurse -Force
  Copy-Item (Join-Path $PSScriptRoot "pipeline.tftest.hcl") (Join-Path $workRoot "pipeline.tftest.hcl") -Force

  $tfSource = (Get-ChildItem $workRoot -Filter "*.tf" | Get-Content -Raw) -join "`n"
  Assert-AwsProviderContract $tfSource
  foreach ($needle in @("aws_s3_bucket_notification", "aws_sns_topic_policy", "manifest_contract", "depends_on", "数字标识不得有前导零")) {
    if ($tfSource -notmatch [regex]::Escape($needle)) { throw "缺少 Terraform 实现：$needle" }
  }
  $scriptSource = (Get-ChildItem (Join-Path $workRoot "scripts") -Filter "*.ps1" | Get-Content -Raw) -join "`n"
  foreach ($needle in @("publish.tfplan", "show -json", "-detailed-exitcode", "state pull", "state push -force", "-refresh-only", "-refresh=false", "approvedReplacementAddresses", "unsafeDeleteAddresses", "rollback.json")) {
    if ($scriptSource -notmatch [regex]::Escape($needle)) { throw "缺少流水线实现：$needle" }
  }

  Set-Location $workRoot
  & terraform fmt -check -recursive
  if ($LASTEXITCODE -ne 0) { throw "terraform fmt failed" }
  & terraform init -input=false -no-color
  if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }
  & terraform validate -no-color
  if ($LASTEXITCODE -ne 0) { throw "terraform validate failed" }

  $testOutput = @(& terraform test -no-color 2>&1)
  $testExit = $LASTEXITCODE
  $testOutput | ForEach-Object { Write-Host $_ }
  $testText = $testOutput -join "`n"
  if ($testExit -ne 0) { throw "canonical tests 失败，exit code=$testExit" }
  if ([regex]::Matches($testText, '(?m)^Success! 5 passed, 0 failed\.$').Count -ne 1) {
    throw "必须精确通过 5/5 canonical tests。"
  }
  Remove-Item (Join-Path $workRoot "pipeline.tftest.hcl") -Force
  Set-Location $originalLocation

  & (Join-Path $workRoot "scripts\publish.ps1") -WorkingDirectory $workRoot -LocalstackEndpoint $LocalstackEndpoint -NamePrefix $prefix -ManifestPath $manifestV1 -ReleaseVersion "1.0.0"
  & (Join-Path $workRoot "scripts\state-drill.ps1") -WorkingDirectory $workRoot -LocalstackEndpoint $LocalstackEndpoint -NamePrefix $prefix -ManifestPath $manifestV1 -ReleaseVersion "1.0.0"
  & (Join-Path $workRoot "scripts\recovery-drill.ps1") -WorkingDirectory $workRoot -LocalstackEndpoint $LocalstackEndpoint -NamePrefix $prefix -ManifestPath $manifestV1 -ReleaseVersion "1.0.0"

  $activeManifest = $manifestV2
  $activeVersion = "1.1.0"
  & (Join-Path $workRoot "scripts\publish.ps1") -WorkingDirectory $workRoot -LocalstackEndpoint $LocalstackEndpoint -NamePrefix $prefix -ManifestPath $manifestV2 -ReleaseVersion "1.1.0"

  $expectedEvidence = @(
    "plan-audit-1.0.0.json",
    "publish-1.0.0.json",
    "state-restore.json",
    "drift-recovery.json",
    "rollback.json",
    "plan-audit-1.1.0.json",
    "publish-1.1.0.json"
  )
  foreach ($evidence in $expectedEvidence) {
    if (-not (Test-Path (Join-Path $workRoot ".evidence\$evidence"))) { throw "缺少 evidence: $evidence" }
  }

  $initialAudit = Get-Content (Join-Path $workRoot ".evidence\plan-audit-1.0.0.json") -Raw | ConvertFrom-Json
  $upgradeAudit = Get-Content (Join-Path $workRoot ".evidence\plan-audit-1.1.0.json") -Raw | ConvertFrom-Json
  if ($initialAudit.delete_count -ne 0 -or $initialAudit.unsafe_delete_count -ne 0) {
    throw "初次发布不应包含 delete。"
  }
  if ($upgradeAudit.delete_count -ne 1 -or $upgradeAudit.unsafe_delete_count -ne 0 -or @($upgradeAudit.approved_replacements) -notcontains "aws_s3_object.manifest") {
    throw "v1→v2 必须只批准 manifest 的单一安全 replacement。"
  }
  $rollback = Get-Content (Join-Path $workRoot ".evidence\rollback.json") -Raw | ConvertFrom-Json
  if (-not $rollback.state_unchanged -or -not $rollback.refresh_disabled) { throw "失败发布没有证明 refresh=false 下 state 不变。" }

  Set-Location $workRoot
  $objectKey = (& terraform output -raw object_key).Trim()
  if ($LASTEXITCODE -ne 0 -or $objectKey -ne "releases/1.1.0/manifest.json") { throw "真实升级未切换到 v2 object key。" }
  & terraform plan -detailed-exitcode -input=false -no-color "-var=name_prefix=$prefix" "-var=localstack_endpoint=$LocalstackEndpoint" "-var=manifest_path=$manifestV2" "-var=release_version=1.1.0" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "v2 发布后必须 clean plan。" }
  Set-Location $originalLocation
  Assert-PublishObjectsAfterUpgrade
}
finally {
  try {
    if (Test-Path $workRoot) {
      Set-Location $workRoot
      if (Test-Path (Join-Path $workRoot "terraform.tfstate")) {
        $destroyOutput = @(& terraform destroy -auto-approve -input=false -no-color "-var=name_prefix=$prefix" "-var=localstack_endpoint=$LocalstackEndpoint" "-var=manifest_path=$activeManifest" "-var=release_version=$activeVersion" 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "cleanup destroy 失败：$($destroyOutput -join "`n")" }
      }
      Assert-S3BucketAbsent
      Assert-SnsTopicAbsent
    }
  }
  finally {
    Set-Location $originalLocation
    Remove-Item $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "PASS: 精确 5/5 canonical tests；真实 v1→v2 安全 replacement、全部恢复 evidence、clean plan、destroy 与远端零残留已验证。"
