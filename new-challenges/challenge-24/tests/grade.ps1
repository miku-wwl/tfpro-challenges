[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "..\starter"),
  [string]$LocalstackEndpoint = "http://localhost:4566",
  [switch]$SkipE2E
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-LoopbackEndpoint([string]$Endpoint) {
  $uri = [Uri]$Endpoint
  if ($uri.Scheme -notin @("http", "https") -or $uri.Host -notin @("localhost", "127.0.0.1", "::1")) {
    throw "拒绝非 loopback endpoint: $Endpoint"
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

function Assert-PlanProviderAndSlotContract($Plan) {
  $providerKeys = @($Plan.configuration.provider_config.PSObject.Properties.Name | Sort-Object)
  if (($providerKeys -join ",") -ne "aws,aws.audit,aws.dr,aws.primary") {
    throw "plan provider 配置必须精确包含 primary、dr、audit 三 alias，且不得有额外配置。"
  }

  $regions = @{ primary = "primary_region"; dr = "dr_region"; audit = "audit_region" }
  foreach ($slot in @("primary", "dr", "audit")) {
    $config = $Plan.configuration.provider_config.PSObject.Properties["aws.$slot"].Value
    if ($config.alias -ne $slot) { throw "plan 中 aws.$slot alias 不匹配。" }
    $expressions = $config.expressions
    if ($expressions.access_key.constant_value -ne "test" -or $expressions.secret_key.constant_value -ne "test") { throw "aws.$slot 凭证不是 test/test。" }
    foreach ($skip in @("skip_credentials_validation", "skip_metadata_api_check", "skip_requesting_account_id")) {
      if ($expressions.$skip.constant_value -ne $true) { throw "aws.$slot 缺少 $skip=true。" }
    }
    if ($expressions.s3_use_path_style.constant_value -ne $true) { throw "aws.$slot 缺少 s3_use_path_style=true。" }
    if ((@($expressions.region.references) -join ",") -ne "var.$($regions[$slot])") { throw "aws.$slot region 引用错误。" }
    $endpointObjects = @($expressions.endpoints)
    if ($endpointObjects.Count -ne 1) { throw "aws.$slot 必须有一个 endpoints block。" }
    $endpointKeys = @($endpointObjects[0].PSObject.Properties.Name | Sort-Object)
    if (($endpointKeys -join ",") -ne "iam,s3,sts") { throw "aws.$slot endpoints 必须精确包含 IAM/S3/STS。" }
    foreach ($service in @("iam", "s3", "sts")) {
      if ((@($endpointObjects[0].$service.references) -join ",") -ne "var.localstack_endpoint") {
        throw "aws.$slot 的 $service endpoint 没有引用 var.localstack_endpoint。"
      }
    }
  }

  $expectedSlots = [ordered]@{
    "aws_iam_policy.audit"                         = "aws.audit"
    "aws_iam_role.audit"                           = "aws.audit"
    "aws_iam_role_policy_attachment.audit"         = "aws.audit"
    "aws_s3_bucket.dr"                             = "aws.dr"
    "aws_s3_bucket.primary"                        = "aws.primary"
    "data.aws_caller_identity.audit"               = "aws.audit"
    "data.aws_caller_identity.dr"                  = "aws.dr"
    "data.aws_caller_identity.primary"             = "aws.primary"
    "data.aws_region.audit"                        = "aws.audit"
    "data.aws_region.dr"                           = "aws.dr"
    "data.aws_region.primary"                      = "aws.primary"
  }
  $resources = @($Plan.configuration.root_module.module_calls.platform.module.resources)
  if ($resources.Count -ne $expectedSlots.Count) { throw "platform module 必须精确包含 5 个 managed resource 与 6 个 data block。" }
  foreach ($entry in $expectedSlots.GetEnumerator()) {
    $matches = @($resources | Where-Object { $_.address -eq $entry.Key })
    if ($matches.Count -ne 1 -or $matches[0].provider_config_key -ne $entry.Value) {
      throw "$($entry.Key) 必须绑定 $($entry.Value)，实际绑定不匹配。"
    }
  }
}

function Invoke-Terraform([string]$Directory, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0)) {
  & terraform "-chdir=$Directory" @Arguments | Out-Host
  $code = $LASTEXITCODE
  if ($code -notin $AllowedExitCodes) { throw "terraform $($Arguments -join ' ') 失败，exit code=$code" }
  return $code
}

function Invoke-TerraformTest([string]$Directory, [string]$TestDirectory, [int]$ExpectedPassed) {
  $testOutput = @(& terraform "-chdir=$Directory" test "-test-directory=$TestDirectory" -no-color 2>&1)
  $code = $LASTEXITCODE
  $testOutput | Out-Host
  if ($code -ne 0) { throw "terraform test 失败，exit code=$code" }

  $joined = $testOutput -join "`n"
  $summaries = [regex]::Matches($joined, 'Success!\s+([0-9]+) passed,\s+0 failed\.')
  $passedRuns = [regex]::Matches($joined, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$')
  if ($summaries.Count -ne 1 -or [int]$summaries[0].Groups[1].Value -ne $ExpectedPassed -or $passedRuns.Count -ne $ExpectedPassed) {
    throw "terraform test 运行数不精确：期望 $ExpectedPassed，输出摘要或 pass run 数不匹配。"
  }
}

function Copy-Tree([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Where-Object { $_.Name -notin @(".terraform", "terraform.tfstate", "terraform.tfstate.backup") } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
  }
}

Assert-LoopbackEndpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$rootText = (Get-ChildItem -LiteralPath $candidatePath -File -Filter "*.tf" | Get-Content -Raw) -join "`n"
$moduleText = (Get-ChildItem -LiteralPath (Join-Path $candidatePath "modules") -Recurse -File -Filter "*.tf" | Get-Content -Raw) -join "`n"
$allText = "$rootText`n$moduleText"
$safeRootText = Remove-HclComments $rootText
$failures = [System.Collections.Generic.List[string]]::new()

$providerBlocks = @(Get-HclBlocks $safeRootText 'provider\s+"aws"\s*\{')
if ($providerBlocks.Count -ne 3) { $failures.Add("root 必须且只能声明 primary、dr、audit 三个 aws provider block。") }
$regions = @{ primary = "primary_region"; dr = "dr_region"; audit = "audit_region" }
foreach ($slot in @("primary", "dr", "audit")) {
  $slotBlocks = @($providerBlocks | Where-Object { Test-ExactHclAssignment $_ "alias" "`"$slot`"" })
  if ($slotBlocks.Count -ne 1) { $failures.Add("aws.$slot provider block 必须精确出现一次。"); continue }
  $providerBlock = $slotBlocks[0]
  $assignments = @{
    region                      = "var\.$($regions[$slot])"
    access_key                  = '"test"'
    secret_key                  = '"test"'
    skip_credentials_validation = 'true'
    skip_metadata_api_check     = 'true'
    skip_requesting_account_id  = 'true'
    s3_use_path_style           = 'true'
  }
  foreach ($entry in $assignments.GetEnumerator()) {
    if (-not (Test-ExactHclAssignment $providerBlock $entry.Key $entry.Value)) {
      $failures.Add("aws.$slot 必须精确设置 $($entry.Key)。")
    }
  }
  $endpointBlocks = @(Get-HclBlocks $providerBlock 'endpoints\s*\{')
  if ($endpointBlocks.Count -ne 1) { $failures.Add("aws.$slot 必须有且只有一个 endpoints block。"); continue }
  $endpointBlock = $endpointBlocks[0]
  $endpointKeys = @([regex]::Matches($endpointBlock, '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  if (($endpointKeys -join ",") -ne "iam,s3,sts") { $failures.Add("aws.$slot endpoints 必须精确包含 iam、s3、sts。") }
  foreach ($service in @("iam", "s3", "sts")) {
    if (-not (Test-ExactHclAssignment $endpointBlock $service 'var\.localstack_endpoint')) {
      $failures.Add("aws.$slot 的 $service endpoint 必须指向 var.localstack_endpoint。")
    }
  }
}

$platformBlocks = @(Get-HclBlocks $safeRootText 'module\s+"platform"\s*\{')
if ($platformBlocks.Count -ne 1) {
  $failures.Add("root 必须且只能调用一次 module.platform。")
}
else {
  foreach ($slot in @("primary", "dr", "audit")) {
    if (-not (Test-ExactHclAssignment $platformBlocks[0] "aws.$slot" "aws\.$slot")) {
      $failures.Add("root providers map 必须精确设置 aws.$slot = aws.$slot。")
    }
  }
}

if ($moduleText -notmatch 'configuration_aliases\s*=\s*\[aws\.primary,\s*aws\.dr,\s*aws\.audit\]') { $failures.Add("child module 缺少三个 configuration_aliases。") }
if ($allText -match '(?i)(profile\s*=|shared_credentials|assume_role\s*\{|AKIA[0-9A-Z]{16})') { $failures.Add("禁止 profile、共享凭证、AssumeRole 或真实 access key。") }

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  throw "provider 安全/映射契约失败（starter 在完成前应当失败）。"
}

$runId = ([Guid]::NewGuid().ToString("N")).Substring(0, 10)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c24-$runId"
$workDir = Join-Path $tempRoot "candidate"
$testFile = (Resolve-Path (Join-Path $PSScriptRoot "canonical.tftest.hcl")).Path
$namePrefix = "tfpro-c24-$runId"
$primaryBucket = "$namePrefix-primary"
$drBucket = "$namePrefix-dr"
$roleName = "$namePrefix-audit"
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

try {
  Copy-Tree $candidatePath $workDir
  New-Item -ItemType Directory -Force -Path (Join-Path $workDir "tests") | Out-Null
  Copy-Item -LiteralPath $testFile -Destination (Join-Path $workDir "tests\canonical.tftest.hcl")
  Invoke-Terraform $workDir @("init", "-backend=false", "-input=false", "-no-color")
  Invoke-TerraformTest $workDir "tests" 1

  if ($SkipE2E) {
    Write-Host "Challenge 24 mock/contract tests passed."
    return
  }

  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null }
  catch { throw "LocalStack 不可用：$LocalstackEndpoint" }

  $commonVars = @("-var=localstack_endpoint=$LocalstackEndpoint", "-var=name_prefix=$namePrefix")
  $planPath = Join-Path $workDir "apply.tfplan"
  Invoke-Terraform $workDir (@("plan", "-out=$planPath", "-input=false", "-no-color") + $commonVars)
  $planJson = (& terraform "-chdir=$workDir" show -json $planPath) | ConvertFrom-Json -Depth 100
  if ($LASTEXITCODE -ne 0) { throw "无法读取 apply plan JSON。" }
  Assert-PlanProviderAndSlotContract $planJson
  Invoke-Terraform $workDir @("apply", "-input=false", "-no-color", $planPath)

  $diagnostics = (& terraform "-chdir=$workDir" output -json provider_diagnostics) | ConvertFrom-Json -Depth 20
  if ($diagnostics.primary.region -ne "us-east-1" -or $diagnostics.dr.region -ne "us-west-2" -or $diagnostics.audit.region -ne "us-east-2") {
    throw "真实 provider region 诊断不匹配。"
  }
  $unexpectedAccounts = @($diagnostics.primary.account_id, $diagnostics.dr.account_id, $diagnostics.audit.account_id) | Where-Object { $_ -ne "000000000000" }
  if (@($unexpectedAccounts).Count -ne 0) {
    throw "STS caller 不是 LocalStack 测试账号。"
  }

  $cleanCode = Invoke-Terraform $workDir (@("plan", "-detailed-exitcode", "-input=false", "-no-color") + $commonVars) @(0, 2)
  if ($cleanCode -ne 0) { throw "apply 后不是 clean plan。" }
  Invoke-Terraform $workDir (@("destroy", "-auto-approve", "-input=false", "-no-color") + $commonVars)

  & aws --endpoint-url $LocalstackEndpoint s3api head-bucket --bucket $primaryBucket 2>$null
  if ($LASTEXITCODE -eq 0) { throw "primary bucket destroy 后仍存在。" }
  & aws --endpoint-url $LocalstackEndpoint s3api head-bucket --bucket $drBucket 2>$null
  if ($LASTEXITCODE -eq 0) { throw "DR bucket destroy 后仍存在。" }
  & aws --endpoint-url $LocalstackEndpoint iam get-role --role-name $roleName 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { throw "audit role destroy 后仍存在。" }
  Write-Host "Challenge 24 passed: three slots + mock identities + LocalStack STS/S3/IAM + clean plan + exact cleanup."
}
finally {
  if ((Test-Path $workDir) -and (Test-Path (Join-Path $workDir "terraform.tfstate"))) {
    try {
      & terraform "-chdir=$workDir" destroy -auto-approve -input=false -no-color "-var=localstack_endpoint=$LocalstackEndpoint" "-var=name_prefix=$namePrefix" 2>$null | Out-Null
    }
    catch { Write-Warning "兜底 destroy 失败：$($_.Exception.Message)" }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
