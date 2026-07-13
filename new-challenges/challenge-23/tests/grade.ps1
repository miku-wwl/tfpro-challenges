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

function Assert-PlanProviderContract($Plan) {
  $providerKeys = @($Plan.configuration.provider_config.PSObject.Properties.Name)
  if ($providerKeys.Count -ne 1 -or $providerKeys[0] -ne "aws") { throw "plan 必须只解析出默认 aws provider 配置。" }
  $expressions = $Plan.configuration.provider_config.aws.expressions
  if ($expressions.access_key.constant_value -ne "test" -or $expressions.secret_key.constant_value -ne "test") { throw "plan provider 凭证不是固定 test/test。" }
  foreach ($skip in @("skip_credentials_validation", "skip_metadata_api_check", "skip_requesting_account_id")) {
    if ($expressions.$skip.constant_value -ne $true) { throw "plan provider 缺少 $skip=true。" }
  }
  if ((@($expressions.region.references) -join ",") -ne "var.aws_region") { throw "provider region 必须引用 var.aws_region。" }
  $endpointObjects = @($expressions.endpoints)
  if ($endpointObjects.Count -ne 1) { throw "plan provider 必须有一个 endpoints block。" }
  $endpointKeys = @($endpointObjects[0].PSObject.Properties.Name | Sort-Object)
  if (($endpointKeys -join ",") -ne "ec2,sts") { throw "provider endpoint 只能且必须包含 EC2、STS。" }
  foreach ($service in @("ec2", "sts")) {
    if ((@($endpointObjects[0].$service.references) -join ",") -ne "var.localstack_endpoint") {
      throw "$service endpoint 必须引用 var.localstack_endpoint。"
    }
  }
}

function Invoke-Terraform([string]$Directory, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0)) {
  & terraform "-chdir=$Directory" @Arguments | Out-Host
  $code = $LASTEXITCODE
  if ($code -notin $AllowedExitCodes) {
    throw "terraform $($Arguments -join ' ') 失败，exit code=$code"
  }
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
$allTerraform = (Get-ChildItem -LiteralPath $candidatePath -Recurse -Filter "*.tf" | Get-Content -Raw) -join "`n"
$rootTerraform = (Get-ChildItem -LiteralPath $candidatePath -File -Filter "*.tf" | Get-Content -Raw) -join "`n"
$safeRootTerraform = Remove-HclComments $rootTerraform
$failures = [System.Collections.Generic.List[string]]::new()

$providerBlocks = @(Get-HclBlocks $safeRootTerraform 'provider\s+"aws"\s*\{')
if ($providerBlocks.Count -ne 1) {
  $failures.Add("root 必须且只能有一个默认 aws provider block。")
}
else {
  $providerBlock = $providerBlocks[0]
  $providerAssignments = @{
    region                      = 'var\.aws_region'
    access_key                  = '"test"'
    secret_key                  = '"test"'
    skip_credentials_validation = 'true'
    skip_metadata_api_check     = 'true'
    skip_requesting_account_id  = 'true'
  }
  foreach ($entry in $providerAssignments.GetEnumerator()) {
    if (-not (Test-ExactHclAssignment $providerBlock $entry.Key $entry.Value)) {
      $failures.Add("aws provider 必须精确设置 $($entry.Key) = $($entry.Value -replace '\\', '')。")
    }
  }
  $endpointBlocks = @(Get-HclBlocks $providerBlock 'endpoints\s*\{')
  if ($endpointBlocks.Count -ne 1) {
    $failures.Add("aws provider 必须有且只有一个 endpoints block。")
  }
  else {
    $endpointBlock = $endpointBlocks[0]
    $endpointKeys = @([regex]::Matches($endpointBlock, '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    if (($endpointKeys -join ",") -ne "ec2,sts") { $failures.Add("endpoints 只能且必须包含 ec2、sts。") }
    foreach ($service in @("ec2", "sts")) {
      if (-not (Test-ExactHclAssignment $endpointBlock $service 'var\.localstack_endpoint')) {
        $failures.Add("$service endpoint 必须精确指向 var.localstack_endpoint。")
      }
    }
  }
}

if ($allTerraform -match "(?m)^\s*count\s*=") { $failures.Add("仍存在 count；目标实现必须用具名 for_each。") }
$movedMatches = @($allTerraform | Select-String -Pattern "(?m)^\s*moved\s*\{" -AllMatches | ForEach-Object { $_.Matches })
if ($movedMatches.Count -lt 5) { $failures.Add("至少需要五个显式 moved blocks。") }
if ($allTerraform -notmatch 'module\s+"network"') { $failures.Add("root 必须调用 module.network。") }
if ($allTerraform -notmatch 'for_each\s*=') { $failures.Add("嵌套模块必须使用 for_each。") }
if ($allTerraform -notmatch 'output\s+"network_v2"') { $failures.Add("缺少 network_v2 output。") }
if ($allTerraform -match '(?i)(AKIA[0-9A-Z]{16}|secret_key\s*=\s*"(?!test"))') { $failures.Add("检测到疑似真实 AWS 凭证。") }

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  throw "结构契约失败（starter 在完成前应当失败）。"
}

$runId = ([Guid]::NewGuid().ToString("N")).Substring(0, 10)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c23-$runId"
$mockDir = Join-Path $tempRoot "mock"
$workDir = Join-Path $tempRoot "migration"
$legacyFixture = (Resolve-Path (Join-Path $PSScriptRoot "..\fixtures\legacy")).Path
$testFile = (Resolve-Path (Join-Path $PSScriptRoot "canonical.tftest.hcl")).Path
$namePrefix = "tfpro-c23-$runId"
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

try {
  Copy-Tree $candidatePath $mockDir
  New-Item -ItemType Directory -Force -Path (Join-Path $mockDir "tests") | Out-Null
  Copy-Item -LiteralPath $testFile -Destination (Join-Path $mockDir "tests\canonical.tftest.hcl")
  Invoke-Terraform $mockDir @("init", "-backend=false", "-input=false", "-no-color")
  Invoke-TerraformTest $mockDir "tests" 1

  if ($SkipE2E) {
    Write-Host "Challenge 23 mock/contract tests passed."
    return
  }

  try {
    Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null
  }
  catch {
    throw "LocalStack 不可用：$LocalstackEndpoint"
  }

  Copy-Tree $legacyFixture $workDir
  Invoke-Terraform $workDir @("init", "-input=false", "-no-color")
  Invoke-Terraform $workDir @("apply", "-auto-approve", "-input=false", "-no-color", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=name_prefix=$namePrefix")

  Get-ChildItem -LiteralPath $workDir -Filter "*.tf" | Remove-Item -Force
  Copy-Tree $candidatePath $workDir
  Invoke-Terraform $workDir @("init", "-input=false", "-no-color")
  $planPath = Join-Path $workDir "refactor.tfplan"
  Invoke-Terraform $workDir @("plan", "-out=$planPath", "-input=false", "-no-color", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=name_prefix=$namePrefix")
  $planJson = (& terraform "-chdir=$workDir" show -json $planPath) | ConvertFrom-Json -Depth 100
  if ($LASTEXITCODE -ne 0) { throw "无法读取迁移 plan JSON。" }
  Assert-PlanProviderContract $planJson
  $changes = @($planJson.resource_changes)
  $mutations = @($changes | Where-Object { (@($_.change.actions) -join ",") -ne "no-op" })
  if ($mutations.Count -ne 0) {
    throw "迁移不是零变更：$((@($mutations.address) -join ', '))"
  }
  $movedCount = @($changes | Where-Object { $_.previous_address }).Count
  if ($movedCount -ne 5) { throw "应识别 5 个 moved 地址，实际为 $movedCount。" }

  Invoke-Terraform $workDir @("apply", "-input=false", "-no-color", $planPath)
  $expectedAddresses = @(
    'module.network.aws_vpc.this',
    'module.network.module.security_group["app"].aws_security_group.this',
    'module.network.module.security_group["ops"].aws_security_group.this',
    'module.network.module.subnet["app-a"].aws_subnet.this',
    'module.network.module.subnet["app-b"].aws_subnet.this'
  )
  $stateAddresses = @(& terraform "-chdir=$workDir" state list)
  if ($LASTEXITCODE -ne 0) { throw "terraform state list 失败。" }
  if (@(Compare-Object $expectedAddresses $stateAddresses).Count -ne 0) {
    throw "最终 state 地址不符合具名嵌套模块合同。"
  }
  $output = (& terraform "-chdir=$workDir" output -json network_v2) | ConvertFrom-Json -Depth 20
  if ($output.schema_version -ne 2) { throw "network_v2.schema_version 不是 2。" }

  $cleanCode = Invoke-Terraform $workDir @("plan", "-detailed-exitcode", "-input=false", "-no-color", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=name_prefix=$namePrefix") @(0, 2)
  if ($cleanCode -ne 0) { throw "迁移后 clean plan 仍有变更。" }

  Invoke-Terraform $workDir @("destroy", "-auto-approve", "-input=false", "-no-color", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=name_prefix=$namePrefix")
  $remaining = @(& terraform "-chdir=$workDir" state list)
  if ($remaining.Count -ne 0) { throw "destroy 后 state 非空。" }
  $remainingVpcs = & aws --endpoint-url $LocalstackEndpoint ec2 describe-vpcs --filters "Name=tag:Name,Values=$namePrefix-vpc" --query "Vpcs[].VpcId" --output text
  if ($LASTEXITCODE -ne 0 -or -not [string]::IsNullOrWhiteSpace(($remainingVpcs -join ""))) {
    throw "destroy 后仍检测到本题 VPC。"
  }
  Write-Host "Challenge 23 passed: mock + 5 moved addresses + zero-change migration + clean plan + destroy."
}
finally {
  if ((Test-Path $workDir) -and (Test-Path (Join-Path $workDir "terraform.tfstate"))) {
    try {
      & terraform "-chdir=$workDir" destroy -auto-approve -input=false -no-color "-var=localstack_endpoint=$LocalstackEndpoint" "-var=name_prefix=$namePrefix" 2>$null | Out-Null
      if ($LASTEXITCODE -ne 0) {
        Get-ChildItem -LiteralPath $workDir -Filter "*.tf" | Remove-Item -Force
        Copy-Tree $legacyFixture $workDir
        & terraform "-chdir=$workDir" init -input=false -no-color 2>$null | Out-Null
        & terraform "-chdir=$workDir" destroy -auto-approve -input=false -no-color "-var=localstack_endpoint=$LocalstackEndpoint" "-var=name_prefix=$namePrefix" 2>$null | Out-Null
      }
    }
    catch { Write-Warning "兜底 destroy 失败：$($_.Exception.Message)" }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
