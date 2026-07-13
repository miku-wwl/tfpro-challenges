[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "..\starter"),
  [string]$LocalstackEndpoint = "http://localhost:4566",
  [switch]$SkipE2E
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-LoopbackEndpoint([string]$Endpoint) {
  if ($Endpoint -notmatch '^https?://(?:localhost|127\.0\.0\.1|\[::1\])(?::[0-9]{1,5})?/?$') {
    throw "拒绝不规范或非 loopback endpoint：$Endpoint"
  }
  try { $uri = [Uri]$Endpoint }
  catch { throw "LocalStack endpoint 不是合法 URI：$Endpoint" }
  if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http', 'https') -or $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or
    $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535 -or
    $Endpoint -match '(?i)%2e|%2f|%5c|\\') {
    throw "拒绝包含凭证、路径、查询、fragment 或归一化绕过的 endpoint：$Endpoint"
  }
}

function Remove-HclComments([string]$Text) {
  $builder = [Text.StringBuilder]::new($Text.Length)
  $state = 'code'
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $current = $Text[$i]
    $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
    if ($state -eq 'code') {
      if ($current -eq '"') { [void]$builder.Append($current); $state = 'string' }
      elseif ($current -eq '#') { [void]$builder.Append(' '); $state = 'line' }
      elseif ($current -eq '/' -and $next -eq '/') { [void]$builder.Append('  '); $i++; $state = 'line' }
      elseif ($current -eq '/' -and $next -eq '*') { [void]$builder.Append('  '); $i++; $state = 'block' }
      else { [void]$builder.Append($current) }
    }
    elseif ($state -eq 'string') {
      [void]$builder.Append($current)
      if ($current -eq '\' -and $i + 1 -lt $Text.Length) { $i++; [void]$builder.Append($Text[$i]) }
      elseif ($current -eq '"') { $state = 'code' }
    }
    elseif ($state -eq 'line') {
      if ($current -eq "`n") { [void]$builder.Append($current); $state = 'code' }
      else { [void]$builder.Append(' ') }
    }
    else {
      if ($current -eq '*' -and $next -eq '/') { [void]$builder.Append('  '); $i++; $state = 'code' }
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

function Copy-CleanTree([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Where-Object {
    $_.Name -notin @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup')
  } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
  }
}

function Invoke-Terraform([string]$Directory, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0)) {
  & terraform "-chdir=$Directory" @Arguments | Out-Host
  $code = $LASTEXITCODE
  if ($code -notin $AllowedExitCodes) { throw "terraform $($Arguments -join ' ') 失败，exit code=$code" }
  return $code
}

function Invoke-ExactTerraformTest([string]$Directory, [int]$ExpectedPassed) {
  $output = @(& terraform "-chdir=$Directory" test -test-directory=tests -no-color 2>&1)
  $code = $LASTEXITCODE
  $output | Out-Host
  if ($code -ne 0) { throw "terraform test 失败，exit code=$code" }
  $joined = $output -join "`n"
  $summaries = [regex]::Matches($joined, 'Success!\s+([0-9]+) passed,\s+0 failed\.')
  $passedRuns = [regex]::Matches($joined, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$')
  if ($summaries.Count -ne 1 -or [int]$summaries[0].Groups[1].Value -ne $ExpectedPassed -or $passedRuns.Count -ne $ExpectedPassed) {
    throw "terraform test 运行数不精确：期望 $ExpectedPassed。"
  }
}

function Assert-PlanProviderRouting($Plan) {
  foreach ($slot in @('primary', 'dr')) {
    $config = $Plan.configuration.provider_config.PSObject.Properties["aws.$slot"].Value
    if ($null -eq $config -or $config.alias -ne $slot) { throw "plan 缺少 aws.$slot provider configuration。" }
    $regionVariable = if ($slot -eq 'primary') { 'primary_region' } else { 'dr_region' }
    if ((@($config.expressions.region.references) -join ',') -ne "var.$regionVariable") { throw "aws.$slot region 路由错误。" }
    if ($config.expressions.access_key.constant_value -ne 'test' -or $config.expressions.secret_key.constant_value -ne 'test') {
      throw "aws.$slot plan 凭证不是字面量 test/test。"
    }
    foreach ($skip in @('skip_credentials_validation', 'skip_metadata_api_check', 'skip_requesting_account_id')) {
      if ($config.expressions.$skip.constant_value -ne $true) { throw "aws.$slot 缺少 $skip=true。" }
    }
    $endpointObjects = @($config.expressions.endpoints)
    if ($endpointObjects.Count -ne 1) { throw "aws.$slot 必须精确包含一个 endpoints block。" }
    $keys = @($endpointObjects[0].PSObject.Properties.Name | Sort-Object)
    if (($keys -join ',') -ne 'ec2,iam,sts') { throw "aws.$slot plan endpoints 不精确。" }
    foreach ($service in @('ec2', 'iam', 'sts')) {
      if ((@($endpointObjects[0].$service.references) -join ',') -ne 'var.localstack_endpoint') {
        throw "aws.$slot 的 $service endpoint 引用错误。"
      }
    }
  }

  $expected = [ordered]@{
    'data.aws_ami.primary'                 = 'aws.primary'
    'data.aws_caller_identity.primary'     = 'aws.primary'
    'data.aws_iam_session_context.primary' = 'aws.primary'
    'data.aws_ami.dr'                      = 'aws.dr'
    'data.aws_caller_identity.dr'          = 'aws.dr'
    'data.aws_iam_session_context.dr'      = 'aws.dr'
    'aws_vpc.primary'                      = 'aws.primary'
    'aws_vpc.dr'                           = 'aws.dr'
  }
  $resources = @($Plan.configuration.root_module.module_calls.diagnostics.module.resources)
  $awsResources = @($resources | Where-Object { $_.provider_config_key -like 'aws*' })
  if ($awsResources.Count -ne $expected.Count) { throw "diagnostics module 必须精确包含 8 个 AWS managed/data blocks。" }
  foreach ($entry in $expected.GetEnumerator()) {
    $matches = @($awsResources | Where-Object { $_.address -eq $entry.Key })
    if ($matches.Count -ne 1 -or $matches[0].provider_config_key -ne $entry.Value) {
      throw "$($entry.Key) 必须绑定 $($entry.Value)。"
    }
  }
}

Assert-LoopbackEndpoint $LocalstackEndpoint

$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$rootText = (@(Get-ChildItem -LiteralPath $candidatePath -File -Filter '*.tf') | Get-Content -Raw) -join "`n"
$modulePath = Join-Path $candidatePath 'modules\diagnostics'
if (-not (Test-Path -LiteralPath $modulePath)) { throw "缺少 modules/diagnostics。" }
$moduleText = (@(Get-ChildItem -LiteralPath $modulePath -File -Filter '*.tf') | Get-Content -Raw) -join "`n"
$safeRoot = Remove-HclComments $rootText
$safeModule = Remove-HclComments $moduleText
$safeAll = "$safeRoot`n$safeModule"
$failures = [System.Collections.Generic.List[string]]::new()

$endpointVariables = @(Get-HclBlocks $safeRoot '(?m)^[ \t]*variable\s+"localstack_endpoint"\s*\{')
if ($endpointVariables.Count -ne 1 -or -not (Test-ExactHclAssignment $endpointVariables[0] 'default' '"http://localhost:4566"')) {
  $failures.Add('localstack_endpoint 必须精确声明一次，默认值必须是 http://localhost:4566。')
}

$providerBlocks = @(Get-HclBlocks $safeRoot '(?m)^[ \t]*provider\s+"aws"\s*\{')
if ($providerBlocks.Count -ne 2) { $failures.Add('root 必须且只能声明 aws.primary 与 aws.dr 两个 provider blocks。') }
$regionVariables = @{ primary = 'primary_region'; dr = 'dr_region' }
foreach ($slot in @('primary', 'dr')) {
  $slotBlocks = @($providerBlocks | Where-Object { Test-ExactHclAssignment $_ 'alias' "`"$slot`"" })
  if ($slotBlocks.Count -ne 1) { $failures.Add("aws.$slot provider 必须精确出现一次。"); continue }
  $block = $slotBlocks[0]
  $assignments = @{
    alias                       = "`"$slot`""
    region                      = "var\.$($regionVariables[$slot])"
    access_key                  = '"test"'
    secret_key                  = '"test"'
    skip_credentials_validation = 'true'
    skip_metadata_api_check     = 'true'
    skip_requesting_account_id  = 'true'
  }
  foreach ($entry in $assignments.GetEnumerator()) {
    if (-not (Test-ExactHclAssignment $block $entry.Key $entry.Value)) { $failures.Add("aws.$slot 必须精确设置 $($entry.Key)。") }
  }
  $endpointBlocks = @(Get-HclBlocks $block '(?m)^[ \t]*endpoints\s*\{')
  if ($endpointBlocks.Count -ne 1) { $failures.Add("aws.$slot 必须有且只有一个 endpoints block。"); continue }
  $keys = @([regex]::Matches($endpointBlocks[0], '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  if (($keys -join ',') -ne 'ec2,iam,sts') { $failures.Add("aws.$slot endpoints 必须精确包含 ec2、iam、sts。") }
  foreach ($service in @('ec2', 'iam', 'sts')) {
    if (-not (Test-ExactHclAssignment $endpointBlocks[0] $service 'var\.localstack_endpoint')) {
      $failures.Add("aws.$slot 的 $service endpoint 必须指向 var.localstack_endpoint。")
    }
  }
}

$moduleBlocks = @(Get-HclBlocks $safeRoot '(?m)^[ \t]*module\s+"diagnostics"\s*\{')
if ($moduleBlocks.Count -ne 1) {
  $failures.Add('root 必须且只能调用一次 module.diagnostics。')
}
else {
  foreach ($slot in @('primary', 'dr')) {
    if (-not (Test-ExactHclAssignment $moduleBlocks[0] "aws.$slot" "aws\.$slot")) { $failures.Add("module providers map 缺少 aws.$slot = aws.$slot。") }
  }
}
if ($safeModule -notmatch 'configuration_aliases\s*=\s*\[\s*aws\.primary\s*,\s*aws\.dr\s*\]') {
  $failures.Add('child module 必须声明 [aws.primary, aws.dr] configuration_aliases。')
}
foreach ($type in @('aws_ami', 'aws_caller_identity', 'aws_iam_session_context')) {
  foreach ($slot in @('primary', 'dr')) {
    $blocks = @(Get-HclBlocks $safeModule "(?m)^[ \t]*data\s+`"$type`"\s+`"$slot`"\s*\{")
    if ($blocks.Count -ne 1 -or -not (Test-ExactHclAssignment $blocks[0] 'provider' "aws\.$slot")) {
      $failures.Add("data.$type.$slot 必须精确绑定 aws.$slot。")
    }
  }
}
foreach ($slot in @('primary', 'dr')) {
  $blocks = @(Get-HclBlocks $safeModule "(?m)^[ \t]*resource\s+`"aws_vpc`"\s+`"$slot`"\s*\{")
  if ($blocks.Count -ne 1 -or -not (Test-ExactHclAssignment $blocks[0] 'provider' "aws\.$slot")) {
    $failures.Add("aws_vpc.$slot 必须精确绑定 aws.$slot。")
  }
}
$guardBlocks = @(Get-HclBlocks $safeRoot '(?m)^[ \t]*output\s+"diagnostic_guard"\s*\{')
if ($guardBlocks.Count -ne 1) {
  $failures.Add('root 必须且只能声明一个 output.diagnostic_guard。')
}
else {
  $guardBlock = $guardBlocks[0]
  $preconditions = @(Get-HclBlocks $guardBlock '(?m)^[ \t]*precondition\s*\{')
  if ($preconditions.Count -ne 4) { $failures.Add('diagnostic_guard 必须精确包含 region、AMI、account、issuer 四个 preconditions。') }
  if ($guardBlock -notmatch 'primary\.region\s*!=\s*\r?\n?\s*module\.diagnostics\.diagnostic_contract\.dr\.region') {
    $failures.Add('diagnostic_guard 缺少 primary/dr same-region 拒绝条件。')
  }
  if ([regex]::Matches($guardBlock, 'regex\("\^ami-\[0-9a-f\]\{8,17\}\$"').Count -ne 2) {
    $failures.Add('diagnostic_guard 必须分别验证 primary/dr AMI ID。')
  }
  if ([regex]::Matches($guardBlock, 'regex\("\^\[0-9\]\{12\}\$"').Count -ne 2) {
    $failures.Add('diagnostic_guard 必须分别验证 primary/dr account ID。')
  }
  if ([regex]::Matches($guardBlock, 'issuer_arn').Count -lt 4 -or [regex]::Matches($guardBlock, 'startswith\(').Count -ne 2 -or $guardBlock -notmatch 'arn:aws:iam') {
    $failures.Add('diagnostic_guard 必须分别验证 issuer ARN 格式及其账号归属。')
  }
}
if ($safeAll -match '(?i)(profile\s*=|(?m)^\s*token\s*=|shared_(config|credentials)|assume_role(_with_web_identity)?\s*\{|web_identity_token|credential_process|container_(credentials|authorization)|AKIA[0-9A-Z]{16})') {
  $failures.Add('禁止替代凭证渠道、AssumeRole 或真实 access key。')
}
if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  throw 'Challenge 34 静态 provider/module/data 合同失败（未完成的 starter 应当失败）。'
}

$runId = ([Guid]::NewGuid().ToString('N')).Substring(0, 9)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c34-$runId"
$workDir = Join-Path $tempRoot 'candidate'
$fixtureSource = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures')).Path
$testSource = (Resolve-Path (Join-Path $PSScriptRoot 'canonical.tftest.hcl')).Path
$namePrefix = "tfpro-c34-$runId"
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
$commonVars = @("-var=localstack_endpoint=$LocalstackEndpoint", "-var=name_prefix=$namePrefix")

try {
  Copy-CleanTree $candidatePath $workDir
  Copy-Item -LiteralPath $fixtureSource -Destination (Join-Path $workDir 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $workDir 'tests') | Out-Null
  Copy-Item -LiteralPath $testSource -Destination (Join-Path $workDir 'tests\canonical.tftest.hcl')

  Invoke-Terraform $workDir @('init', '-backend=false', '-input=false', '-no-color')
  Invoke-ExactTerraformTest $workDir 7

  if ($SkipE2E) {
    Write-Host 'Challenge 34 mock/override/expected-failure tests passed.'
    return
  }

  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null }
  catch { throw "LocalStack 不可用：$LocalstackEndpoint" }

  $planPath = Join-Path $workDir 'diagnostics.tfplan'
  Invoke-Terraform $workDir (@('plan', "-out=$planPath", '-input=false', '-no-color') + $commonVars)
  $planJson = (& terraform "-chdir=$workDir" show -json $planPath) | ConvertFrom-Json -Depth 100
  if ($LASTEXITCODE -ne 0) { throw '无法读取 saved plan JSON。' }
  Assert-PlanProviderRouting $planJson
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $planPath)

  $diagnostics = (& terraform "-chdir=$workDir" output -json diagnostic_contract) | ConvertFrom-Json -Depth 20
  if ($LASTEXITCODE -ne 0) { throw '无法读取 diagnostic_contract。' }
  foreach ($slot in @('primary', 'dr')) {
    if ($diagnostics.$slot.account_id -ne '000000000000') { throw "$slot caller identity 不是 LocalStack 测试账号。" }
    if ($diagnostics.$slot.ami_id -notmatch '^ami-[0-9a-f]{8,17}$') { throw "$slot AMI 诊断非法。" }
    if ([string]::IsNullOrWhiteSpace($diagnostics.$slot.issuer_arn)) { throw "$slot session issuer 为空。" }
  }
  $guard = (& terraform "-chdir=$workDir" output -json diagnostic_guard) | ConvertFrom-Json -Depth 10
  if ($LASTEXITCODE -ne 0 -or $guard.validated -ne $true) { throw '真实诊断数据没有通过 output.diagnostic_guard。' }

  foreach ($entry in @(@('us-east-1', "$namePrefix-primary"), @('us-west-2', "$namePrefix-dr"))) {
    $vpcs = @(& aws --endpoint-url $LocalstackEndpoint --region $entry[0] ec2 describe-vpcs --filters "Name=tag:Name,Values=$($entry[1])" --query 'Vpcs[].VpcId' --output text)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($vpcs -join ''))) { throw "真实 LocalStack VPC 不存在：$($entry[1])" }
  }

  $clean = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $commonVars) @(0, 2)
  if ($clean -ne 0) { throw 'apply 后不是 clean plan。' }
  Invoke-Terraform $workDir (@('destroy', '-auto-approve', '-input=false', '-no-color') + $commonVars)

  foreach ($entry in @(@('us-east-1', "$namePrefix-primary"), @('us-west-2', "$namePrefix-dr"))) {
    $vpcs = @(& aws --endpoint-url $LocalstackEndpoint --region $entry[0] ec2 describe-vpcs --filters "Name=tag:Name,Values=$($entry[1])" --query 'Vpcs[].VpcId' --output text)
    if (-not [string]::IsNullOrWhiteSpace(($vpcs -join ''))) { throw "destroy 后 VPC 仍存在：$($entry[1])" }
  }

  Write-Host 'Challenge 34 passed: 7 tests + independent diagnostic failures + exact plan routing + EC2/STS/IAM E2E + cleanup.'
}
finally {
  if ((Test-Path $workDir) -and (Test-Path (Join-Path $workDir 'terraform.tfstate'))) {
    & terraform "-chdir=$workDir" destroy -auto-approve -input=false -no-color @commonVars 2>$null | Out-Null
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
