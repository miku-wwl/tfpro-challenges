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
  Get-ChildItem -LiteralPath $Source -Force | Where-Object { $_.Name -notin @(".terraform", "terraform.tfstate", "terraform.tfstate.backup", ".runtime") } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
  }
}

function Write-BackendConfig([string]$Path, [string]$Bucket, [string]$Key, [string]$Table, [string]$Endpoint) {
  $safeEndpoint = $Endpoint.TrimEnd("/")
  $content = @"
bucket                      = "$Bucket"
key                         = "$Key"
region                      = "us-east-1"
dynamodb_table              = "$Table"
encrypt                     = false
access_key                  = "test"
secret_key                  = "test"
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true
use_path_style              = true
endpoints = {
  s3       = "$safeEndpoint"
  dynamodb = "$safeEndpoint"
}
"@
  [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($false))
}

function Get-RequiredProperty($Object, [string]$Name, [string]$Context) {
  if ($null -eq $Object) { throw "$Context 不存在。" }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { throw "$Context 缺少 $Name。" }
  return $property.Value
}

function Assert-BackendMetadata(
  [string]$Directory,
  [string]$ExpectedBucket,
  [string]$ExpectedKey,
  [string]$ExpectedTable,
  [string]$ExpectedEndpoint
) {
  $metadataPath = Join-Path $Directory ".terraform\terraform.tfstate"
  if (-not (Test-Path -LiteralPath $metadataPath)) { throw "$Directory 缺少 backend metadata。" }
  $metadata = Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json -Depth 100
  $backend = Get-RequiredProperty $metadata "backend" "$Directory metadata"
  if ((Get-RequiredProperty $backend "type" "$Directory backend") -ne "s3") { throw "$Directory backend type 不是 s3。" }
  $config = Get-RequiredProperty $backend "config" "$Directory backend"

  $expectedValues = @{
    bucket         = $ExpectedBucket
    key            = $ExpectedKey
    dynamodb_table = $ExpectedTable
    access_key     = "test"
    secret_key     = "test"
  }
  foreach ($entry in $expectedValues.GetEnumerator()) {
    if ((Get-RequiredProperty $config $entry.Key "$Directory backend config") -ne $entry.Value) {
      throw "$Directory backend metadata 的 $($entry.Key) 不匹配。"
    }
  }
  foreach ($flag in @("skip_credentials_validation", "skip_metadata_api_check", "skip_requesting_account_id", "use_path_style")) {
    if ((Get-RequiredProperty $config $flag "$Directory backend config") -ne $true) {
      throw "$Directory backend metadata 缺少 $flag=true。"
    }
  }
  $endpoints = Get-RequiredProperty $config "endpoints" "$Directory backend config"
  $endpointKeys = @($endpoints.PSObject.Properties.Name | Where-Object { $null -ne $endpoints.PSObject.Properties[$_].Value } | Sort-Object)
  if (($endpointKeys -join ",") -ne "dynamodb,s3") { throw "$Directory backend endpoints 必须精确包含 dynamodb、s3。" }
  foreach ($service in @("dynamodb", "s3")) {
    $value = [string](Get-RequiredProperty $endpoints $service "$Directory backend endpoints")
    Assert-LoopbackEndpoint $value
    if ($value.TrimEnd('/') -ne $ExpectedEndpoint.TrimEnd('/')) { throw "$Directory 的 $service backend endpoint 不匹配。" }
  }
}

function New-TerraformAuditShim([string]$ShimDirectory) {
  New-Item -ItemType Directory -Force -Path $ShimDirectory | Out-Null
  if ($IsWindows) {
    $shimPath = Join-Path $ShimDirectory "terraform.cmd"
    $content = "@echo off`r`n>>`"%TFPRO_AUDIT_LOG%`" echo %*`r`n`"%TFPRO_REAL_TERRAFORM%`" %*`r`nexit /b %ERRORLEVEL%`r`n"
    [IO.File]::WriteAllText($shimPath, $content, [Text.ASCIIEncoding]::new())
  }
  else {
    $shimPath = Join-Path $ShimDirectory "terraform"
    $content = @'
#!/bin/sh
printf '%s\n' "$*" >> "$TFPRO_AUDIT_LOG"
exec "$TFPRO_REAL_TERRAFORM" "$@"
'@
    [IO.File]::WriteAllText($shimPath, $content, [Text.UTF8Encoding]::new($false))
    & chmod +x $shimPath
    if ($LASTEXITCODE -ne 0) { throw "无法创建 terraform audit shim。" }
  }
}

function Invoke-ReleaseAudited(
  [string]$ScriptPath,
  [string[]]$ReleaseArguments,
  [string]$ShimDirectory,
  [string]$LogPath,
  [string]$RealTerraform
) {
  [IO.File]::WriteAllText($LogPath, "", [Text.UTF8Encoding]::new($false))
  $oldPath = $env:PATH
  $oldAuditLog = $env:TFPRO_AUDIT_LOG
  $oldRealTerraform = $env:TFPRO_REAL_TERRAFORM
  $code = -1
  try {
    $env:PATH = "$ShimDirectory$([IO.Path]::PathSeparator)$oldPath"
    $env:TFPRO_AUDIT_LOG = $LogPath
    $env:TFPRO_REAL_TERRAFORM = $RealTerraform
    & pwsh -NoProfile -File $ScriptPath @ReleaseArguments | Out-Host
    $code = $LASTEXITCODE
  }
  finally {
    $env:PATH = $oldPath
    $env:TFPRO_AUDIT_LOG = $oldAuditLog
    $env:TFPRO_REAL_TERRAFORM = $oldRealTerraform
  }
  if ($code -ne 0) { throw "release.ps1 执行失败，exit code=$code。" }
  return @(Get-Content -LiteralPath $LogPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Assert-SavedPlanAudit([string[]]$CommandLines, [string[]]$ExpectedPlans) {
  $applyLines = @($CommandLines | Where-Object { $_ -match '(?i)(^|\s)apply(\s|$)' })
  if ($applyLines.Count -ne $ExpectedPlans.Count) {
    throw "实际 terraform apply 次数不匹配：期望 $($ExpectedPlans.Count)，实际 $($applyLines.Count)。"
  }
  foreach ($line in $applyLines) {
    if ($line -notmatch '(?i)\.tfplan(\s|$|\")' -or $line -match '(?i)-auto-approve') {
      throw "检测到未消费 saved .tfplan 的实际 apply：$line"
    }
  }
  foreach ($planName in $ExpectedPlans) {
    $escaped = [regex]::Escape($planName)
    $planLines = @($CommandLines | Where-Object { $_ -match '(?i)(^|\s)plan(\s|$)' -and $_ -match "(?i)-out=[^\s]*$escaped" })
    $matchingApply = @($applyLines | Where-Object { $_ -match "(?i)$escaped" })
    if ($planLines.Count -ne 1 -or $matchingApply.Count -ne 1) {
      throw "$planName 必须由一次 plan -out 生成，并被一次实际 apply 消费。"
    }
  }
}

Assert-LoopbackEndpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$requiredDirs = @("bootstrap", "producer", "consumer", "scripts")
foreach ($dir in $requiredDirs) {
  if (-not (Test-Path (Join-Path $candidatePath $dir))) { throw "候选目录缺少 $dir/。" }
}

$bootstrapText = (Get-ChildItem (Join-Path $candidatePath "bootstrap") -Filter "*.tf" | Get-Content -Raw) -join "`n"
$producerText = (Get-ChildItem (Join-Path $candidatePath "producer") -Filter "*.tf" | Get-Content -Raw) -join "`n"
$consumerText = (Get-ChildItem (Join-Path $candidatePath "consumer") -Filter "*.tf" | Get-Content -Raw) -join "`n"
$scriptText = Get-Content -Raw (Join-Path $candidatePath "scripts\release.ps1")
$allText = "$bootstrapText`n$producerText`n$consumerText`n$scriptText"
$safeBootstrapText = Remove-HclComments $bootstrapText
$safeConsumerText = Remove-HclComments $consumerText
$failures = [System.Collections.Generic.List[string]]::new()

$bootstrapProviderBlocks = @(Get-HclBlocks $safeBootstrapText 'provider\s+"aws"\s*\{')
if ($bootstrapProviderBlocks.Count -ne 1) {
  $failures.Add("bootstrap 必须且只能声明一个默认 aws provider block。")
}
else {
  $providerBlock = $bootstrapProviderBlocks[0]
  $providerAssignments = @{
    region                      = 'var\.aws_region'
    access_key                  = '"test"'
    secret_key                  = '"test"'
    skip_credentials_validation = 'true'
    skip_metadata_api_check     = 'true'
    skip_requesting_account_id  = 'true'
    s3_use_path_style           = 'true'
  }
  foreach ($entry in $providerAssignments.GetEnumerator()) {
    if (-not (Test-ExactHclAssignment $providerBlock $entry.Key $entry.Value)) {
      $failures.Add("bootstrap aws provider 必须使用字面量安全配置 $($entry.Key)；动态或其他凭证不允许。")
    }
  }
  $endpointBlocks = @(Get-HclBlocks $providerBlock 'endpoints\s*\{')
  if ($endpointBlocks.Count -ne 1) {
    $failures.Add("bootstrap aws provider 必须有且只有一个 endpoints block。")
  }
  else {
    $endpointBlock = $endpointBlocks[0]
    $endpointKeys = @([regex]::Matches($endpointBlock, '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    if (($endpointKeys -join ",") -ne "dynamodb,s3,sts") { $failures.Add("bootstrap endpoints 必须精确包含 dynamodb、s3、sts。") }
    foreach ($service in @("dynamodb", "s3", "sts")) {
      if (-not (Test-ExactHclAssignment $endpointBlock $service 'var\.localstack_endpoint')) {
        $failures.Add("bootstrap $service endpoint 必须指向 var.localstack_endpoint。")
      }
    }
  }
}

$remoteStateBlocks = @(Get-HclBlocks $safeConsumerText 'data\s+"terraform_remote_state"\s+"producer"\s*\{')
if ($remoteStateBlocks.Count -ne 1) {
  $failures.Add("consumer 必须且只能声明一个 producer terraform_remote_state block。")
}
else {
  $remoteStateBlock = $remoteStateBlocks[0]
  $remoteAssignments = @{
    backend                      = '"s3"'
    access_key                   = '"test"'
    secret_key                   = '"test"'
    skip_credentials_validation  = 'true'
    skip_metadata_api_check      = 'true'
    skip_requesting_account_id   = 'true'
    use_path_style               = 'true'
  }
  foreach ($entry in $remoteAssignments.GetEnumerator()) {
    if (-not (Test-ExactHclAssignment $remoteStateBlock $entry.Key $entry.Value)) {
      $failures.Add("terraform_remote_state 必须使用字面量安全配置 $($entry.Key)；动态或其他凭证不允许。")
    }
  }
  $remoteEndpointBlocks = @(Get-HclBlocks $remoteStateBlock 'endpoints\s*=\s*\{')
  if ($remoteEndpointBlocks.Count -ne 1) {
    $failures.Add("terraform_remote_state 必须有且只有一个 endpoints map。")
  }
  else {
    $remoteEndpointBlock = $remoteEndpointBlocks[0]
    $remoteEndpointKeys = @([regex]::Matches($remoteEndpointBlock, '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne "endpoints" } | Sort-Object)
    if (($remoteEndpointKeys -join ",") -ne "s3") { $failures.Add("terraform_remote_state endpoints 必须精确只包含 s3。") }
    if (-not (Test-ExactHclAssignment $remoteEndpointBlock "s3" 'var\.localstack_endpoint')) {
      $failures.Add("terraform_remote_state S3 endpoint 必须指向 var.localstack_endpoint。")
    }
  }
}

if ($bootstrapText -notmatch 'hash_key\s*=\s*"LockID"') { $failures.Add("DynamoDB hash_key 必须为 LockID。") }
if ($bootstrapText -notmatch 'force_destroy\s*=\s*true') { $failures.Add("state bucket 必须支持最终精确清理。") }
if ($producerText -notmatch 'backend\s+"s3"\s*\{') { $failures.Add("producer 最终 backend 必须是部分配置 S3。") }
if ($consumerText -notmatch 'backend\s+"s3"\s*\{') { $failures.Add("consumer 自身 backend 必须是 S3。") }
if ($consumerText -notmatch 'data\s+"terraform_remote_state"\s+"producer"') { $failures.Add("consumer 缺少 producer terraform_remote_state。") }
if ($consumerText -notmatch 'use_path_style\s*=\s*true' -or $consumerText -notmatch 'endpoints\s*=\s*\{') { $failures.Add("remote_state 缺少 LocalStack path-style/endpoints。") }
if ($scriptText -notmatch 'plan.+-out=' -or $scriptText -notmatch 'apply') { $failures.Add("release.ps1 必须保存并应用 plan。") }
if ($scriptText -notmatch 'ORDER:\s*consumer-before-producer') { $failures.Add("release.ps1 缺少 consumer-first destroy 顺序。") }
if ($allText -match '(?i)(AKIA[0-9A-Z]{16}|profile\s*=|shared_credentials)') { $failures.Add("检测到真实凭证/profile 风险。") }

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  throw "远端状态契约失败（starter 在完成前应当失败）。"
}

$runId = ([Guid]::NewGuid().ToString("N")).Substring(0, 10)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c22-$runId"
$mockBootstrap = Join-Path $tempRoot "mock-bootstrap"
$mockProducer = Join-Path $tempRoot "mock-producer"
$runtimeRoot = Join-Path $tempRoot "runtime"
$bootstrap = Join-Path $runtimeRoot "bootstrap"
$producer = Join-Path $runtimeRoot "producer"
$consumer = Join-Path $runtimeRoot "consumer"
$bucket = "tfpro-c22-$runId-state"
$table = "tfpro-c22-$runId-locks"
$prefix = "runs/$runId"
$producerKey = "$prefix/producer.tfstate"
$consumerKey = "$prefix/consumer.tfstate"
$backendDir = Join-Path $runtimeRoot ".backend"
$producerBackend = Join-Path $backendDir "producer.hcl"
$consumerBackend = Join-Path $backendDir "consumer.hcl"
$auditShim = Join-Path $tempRoot "terraform-audit-shim"
$auditLog = Join-Path $tempRoot "terraform-commands.log"
$realTerraform = (Get-Command terraform -CommandType Application | Select-Object -First 1).Source
$localBackendFixture = (Resolve-Path (Join-Path $PSScriptRoot "..\fixtures\local-backend.tf")).Path
$releaseScript = Join-Path $runtimeRoot "scripts\release.ps1"
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

try {
  Copy-Tree (Join-Path $candidatePath "bootstrap") $mockBootstrap
  New-Item -ItemType Directory -Force -Path (Join-Path $mockBootstrap "tests") | Out-Null
  Copy-Item (Join-Path $PSScriptRoot "bootstrap.tftest.hcl") (Join-Path $mockBootstrap "tests\bootstrap.tftest.hcl")
  Invoke-Terraform $mockBootstrap @("init", "-backend=false", "-input=false", "-no-color")
  Invoke-TerraformTest $mockBootstrap "tests" 1

  Copy-Tree (Join-Path $candidatePath "producer") $mockProducer
  New-Item -ItemType Directory -Force -Path (Join-Path $mockProducer "tests") | Out-Null
  Copy-Item (Join-Path $PSScriptRoot "producer.tftest.hcl") (Join-Path $mockProducer "tests\producer.tftest.hcl")
  Invoke-Terraform $mockProducer @("init", "-backend=false", "-input=false", "-no-color")
  Invoke-TerraformTest $mockProducer "tests" 1

  if ($SkipE2E) {
    Write-Host "Challenge 22 canonical tests passed."
    return
  }

  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null }
  catch { throw "LocalStack 不可用：$LocalstackEndpoint" }

  Copy-Tree (Join-Path $candidatePath "bootstrap") $bootstrap
  Copy-Tree (Join-Path $candidatePath "producer") $producer
  Copy-Tree (Join-Path $candidatePath "consumer") $consumer
  Copy-Tree (Join-Path $candidatePath "scripts") (Join-Path $runtimeRoot "scripts")
  New-Item -ItemType Directory -Force -Path $backendDir | Out-Null
  New-TerraformAuditShim $auditShim
  Write-BackendConfig $producerBackend $bucket $producerKey $table $LocalstackEndpoint
  Write-BackendConfig $consumerBackend $bucket $consumerKey $table $LocalstackEndpoint

  $bootstrapVars = @("-var=localstack_endpoint=$LocalstackEndpoint", "-var=state_bucket_name=$bucket", "-var=lock_table_name=$table")
  Invoke-Terraform $bootstrap @("init", "-input=false", "-no-color")
  Invoke-Terraform $bootstrap (@("apply", "-auto-approve", "-input=false", "-no-color") + $bootstrapVars)

  Remove-Item -LiteralPath (Join-Path $producer "backend.tf") -Force
  Copy-Item -LiteralPath $localBackendFixture -Destination (Join-Path $producer "local-backend.tf")
  Invoke-Terraform $producer @("init", "-input=false", "-no-color")
  Invoke-Terraform $producer @("apply", "-auto-approve", "-input=false", "-no-color", "-var=release_id=legacy")
  $legacyAddresses = @(& terraform "-chdir=$producer" state list)
  if ($legacyAddresses -notcontains "terraform_data.contract") { throw "legacy local state 未建立预期地址。" }

  Remove-Item -LiteralPath (Join-Path $producer "local-backend.tf") -Force
  Copy-Item -LiteralPath (Join-Path $candidatePath "producer\backend.tf") -Destination (Join-Path $producer "backend.tf")
  Invoke-Terraform $producer @("init", "-migrate-state", "-force-copy", "-input=false", "-no-color", "-backend-config=$producerBackend")
  Assert-BackendMetadata $producer $bucket $producerKey $table $LocalstackEndpoint
  $migratedAddresses = @(& terraform "-chdir=$producer" state list)
  if ($migratedAddresses -notcontains "terraform_data.contract") { throw "迁移后资源身份丢失。" }
  & aws --endpoint-url $LocalstackEndpoint s3api head-object --bucket $bucket --key $producerKey | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "producer state object 未写入 S3。" }

  $deployArguments = @("-Action", "Deploy", "-Root", $runtimeRoot, "-StateBucket", $bucket, "-LockTable", $table, "-StatePrefix", $prefix, "-LocalstackEndpoint", $LocalstackEndpoint, "-ReleaseId", "release-$runId")
  $deployAudit = @(Invoke-ReleaseAudited -ScriptPath $releaseScript -ReleaseArguments $deployArguments -ShimDirectory $auditShim -LogPath $auditLog -RealTerraform $realTerraform)
  Assert-SavedPlanAudit -CommandLines $deployAudit -ExpectedPlans @("producer-apply.tfplan", "consumer-apply.tfplan")
  Assert-BackendMetadata $producer $bucket $producerKey $table $LocalstackEndpoint
  Assert-BackendMetadata $consumer $bucket $consumerKey $table $LocalstackEndpoint
  $observed = (& terraform "-chdir=$consumer" output -json observed_contract) | ConvertFrom-Json -Depth 20
  if ($observed.schema_version -ne 2 -or $observed.release_id -ne "release-$runId") { throw "consumer 未观察到 producer schema v2 新发布。" }

  $producerClean = Invoke-Terraform $producer @("plan", "-detailed-exitcode", "-input=false", "-no-color", "-var=release_id=release-$runId") @(0, 2)
  if ($producerClean -ne 0) { throw "producer 不是 clean plan。" }
  $consumerVars = @("-var=state_bucket=$bucket", "-var=producer_state_key=$producerKey", "-var=aws_region=us-east-1", "-var=localstack_endpoint=$LocalstackEndpoint")
  $consumerClean = Invoke-Terraform $consumer (@("plan", "-detailed-exitcode", "-input=false", "-no-color") + $consumerVars) @(0, 2)
  if ($consumerClean -ne 0) { throw "consumer 不是 clean plan。" }
  & aws --endpoint-url $LocalstackEndpoint s3api head-object --bucket $bucket --key $consumerKey | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "consumer state object 未写入 S3。" }

  $destroyArguments = @("-Action", "Destroy", "-Root", $runtimeRoot, "-StateBucket", $bucket, "-LockTable", $table, "-StatePrefix", $prefix, "-LocalstackEndpoint", $LocalstackEndpoint, "-ReleaseId", "release-$runId")
  $destroyAudit = @(Invoke-ReleaseAudited -ScriptPath $releaseScript -ReleaseArguments $destroyArguments -ShimDirectory $auditShim -LogPath $auditLog -RealTerraform $realTerraform)
  Assert-SavedPlanAudit -CommandLines $destroyAudit -ExpectedPlans @("consumer-destroy.tfplan", "producer-destroy.tfplan")
  $destroyOrder = @(Get-Content (Join-Path $runtimeRoot ".runtime\destroy-order.log"))
  if ((@($destroyOrder) -join ",") -ne "consumer,producer") { throw "destroy 顺序不是 consumer,producer。" }
  if (@(& terraform "-chdir=$consumer" state list).Count -ne 0 -or @(& terraform "-chdir=$producer" state list).Count -ne 0) {
    throw "发布层 destroy 后远端 state 仍有资源。"
  }

  Invoke-Terraform $bootstrap (@("destroy", "-auto-approve", "-input=false", "-no-color") + $bootstrapVars)
  & aws --endpoint-url $LocalstackEndpoint s3api head-bucket --bucket $bucket 2>$null
  if ($LASTEXITCODE -eq 0) { throw "bootstrap destroy 后 state bucket 仍存在。" }
  & aws --endpoint-url $LocalstackEndpoint dynamodb describe-table --table-name $table 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { throw "bootstrap destroy 后 lock table 仍存在。" }
  Write-Host "Challenge 22 passed: mock + local-to-S3 migration + DynamoDB lock + remote state + saved plans + ordered destroy."
}
finally {
  if (Test-Path $releaseScript) {
    try {
      & pwsh -NoProfile -File $releaseScript -Action Destroy -Root $runtimeRoot -StateBucket $bucket -LockTable $table -StatePrefix $prefix -LocalstackEndpoint $LocalstackEndpoint -ReleaseId "release-$runId" 2>$null | Out-Null
    }
    catch { Write-Warning "兜底 workload destroy 失败：$($_.Exception.Message)" }
  }
  if ((Test-Path $bootstrap) -and (Test-Path (Join-Path $bootstrap "terraform.tfstate"))) {
    try { & terraform "-chdir=$bootstrap" destroy -auto-approve -input=false -no-color "-var=localstack_endpoint=$LocalstackEndpoint" "-var=state_bucket_name=$bucket" "-var=lock_table_name=$table" 2>$null | Out-Null }
    catch { Write-Warning "兜底 bootstrap destroy 失败：$($_.Exception.Message)" }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
