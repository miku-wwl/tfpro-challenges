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
  if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @("http", "https") -or $uri.DnsSafeHost -notin @("localhost", "127.0.0.1", "::1") -or
    $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535 -or
    $Endpoint -match '(?i)%2e|%2f|%5c|\\') {
    throw "拒绝包含凭证、路径、查询、fragment 或归一化绕过的 endpoint：$Endpoint"
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

function Copy-CleanTree([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Where-Object {
    $_.Name -notin @(".terraform", ".terraform.lock.hcl", "terraform.tfstate", "terraform.tfstate.backup", "terraform.tfstate.d")
  } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
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

function Invoke-ExactTerraformTest([string]$Directory, [string]$TestDirectory, [int]$ExpectedPassed) {
  $output = @(& terraform "-chdir=$Directory" test "-test-directory=$TestDirectory" -no-color 2>&1)
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

function Get-WorkspaceContract([string]$Directory) {
  $json = (& terraform "-chdir=$Directory" output -json release_contract)
  if ($LASTEXITCODE -ne 0) { throw "读取 release_contract 失败。" }
  return ($json | ConvertFrom-Json -Depth 20)
}

Assert-LoopbackEndpoint $LocalstackEndpoint

$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$rootFiles = @(Get-ChildItem -LiteralPath $candidatePath -File -Filter "*.tf")
if ($rootFiles.Count -eq 0) { throw "Candidate 中没有 Terraform 文件。" }
$allText = ($rootFiles | Get-Content -Raw) -join "`n"
$safeText = Remove-HclComments $allText
$failures = [System.Collections.Generic.List[string]]::new()

$endpointVariables = @(Get-HclBlocks $safeText '(?m)^[ \t]*variable\s+"localstack_endpoint"\s*\{')
if ($endpointVariables.Count -ne 1 -or -not (Test-ExactHclAssignment $endpointVariables[0] 'default' '"http://localhost:4566"')) {
  $failures.Add("localstack_endpoint 必须精确声明一次，默认值必须是 http://localhost:4566。")
}

$providerBlocks = @(Get-HclBlocks $safeText '(?m)^[ \t]*provider\s+"aws"\s*\{')
if ($providerBlocks.Count -ne 1) {
  $failures.Add("必须且只能声明一个 aws provider block。")
}
else {
  $provider = $providerBlocks[0]
  $assignments = @{
    region                       = 'var\.aws_region'
    access_key                   = '"test"'
    secret_key                   = '"test"'
    skip_credentials_validation = 'true'
    skip_metadata_api_check      = 'true'
    skip_requesting_account_id   = 'true'
    s3_use_path_style            = 'true'
  }
  foreach ($entry in $assignments.GetEnumerator()) {
    if (-not (Test-ExactHclAssignment $provider $entry.Key $entry.Value)) {
      $failures.Add("aws provider 必须精确设置 $($entry.Key)。")
    }
  }
  $endpointBlocks = @(Get-HclBlocks $provider '(?m)^[ \t]*endpoints\s*\{')
  if ($endpointBlocks.Count -ne 1) {
    $failures.Add("aws provider 必须有且只有一个 endpoints block。")
  }
  else {
    $keys = @([regex]::Matches($endpointBlocks[0], '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
    if (($keys -join ',') -ne 's3,sns,sts') { $failures.Add("endpoints 必须精确包含 s3、sns、sts。") }
    foreach ($service in @('s3', 'sns', 'sts')) {
      if (-not (Test-ExactHclAssignment $endpointBlocks[0] $service 'var\.localstack_endpoint')) {
        $failures.Add("$service endpoint 必须指向 var.localstack_endpoint。")
      }
    }
  }
}

foreach ($type in @('aws_s3_bucket', 'aws_sns_topic')) {
  $blocks = @(Get-HclBlocks $safeText "resource\s+`"$type`"\s+`"release`"\s*\{")
  if ($blocks.Count -ne 1 -or -not (Test-ExactHclAssignment $blocks[0] 'for_each' 'local\.active_services')) {
    $failures.Add("$type.release 必须精确使用 local.active_services 作为 for_each。")
  }
}
$bucketBlocks = @(Get-HclBlocks $safeText '(?m)^[ \t]*resource\s+"aws_s3_bucket"\s+"release"\s*\{')
$topicBlocks = @(Get-HclBlocks $safeText '(?m)^[ \t]*resource\s+"aws_sns_topic"\s+"release"\s*\{')
if ($bucketBlocks.Count -ne 1 -or -not (Test-ExactHclAssignment $bucketBlocks[0] 'bucket' '"\$\{var\.name_prefix\}-\$\{terraform\.workspace\}-\$\{each\.key\}-\$\{var\.run_id\}"')) {
  $failures.Add('bucket 实际名称必须精确包含 terraform.workspace。')
}
if ($topicBlocks.Count -ne 1 -or -not (Test-ExactHclAssignment $topicBlocks[0] 'name' '"\$\{var\.name_prefix\}-\$\{terraform\.workspace\}-\$\{each\.key\}-\$\{var\.run_id\}-events"')) {
  $failures.Add('topic 实际名称必须精确包含 terraform.workspace。')
}
if ($safeText -notmatch 'resource\s+"terraform_data"\s+"catalog_guard"' -or $safeText -notmatch 'contains\s*\(\s*\["dev",\s*"stage",\s*"prod"\]') {
  $failures.Add("缺少 dev/stage/prod workspace guard。")
}
if ($safeText -notmatch '\bduplicate_services\b' -or $safeText -notmatch 'csvdecode\s*\(' -or $safeText -notmatch 'for\s+service\s*,\s*rows\s+in\s+local\.all_groups') {
  $failures.Add("重复检测必须覆盖全部 normalized rows，而不是只覆盖 enabled rows。")
}
$outputBlocks = @(Get-HclBlocks $safeText '(?m)^[ \t]*output\s+"release_contract"\s*\{')
if ($outputBlocks.Count -ne 1 -or $outputBlocks[0] -notmatch 'aws_s3_bucket\.release' -or $outputBlocks[0] -notmatch 'aws_sns_topic\.release' -or $outputBlocks[0] -notmatch 'terraform\.workspace') {
  $failures.Add('release_contract 必须从实际 S3/SNS resources 与 terraform.workspace 派生。')
}
if ($safeText -match '(?i)(profile\s*=|(?m)^\s*token\s*=|shared_(config|credentials)|assume_role(_with_web_identity)?\s*\{|web_identity_token|credential_process|container_(credentials|authorization)|AKIA[0-9A-Z]{16})') {
  $failures.Add("禁止替代凭证渠道、AssumeRole 或真实 access key。")
}
if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  throw "Challenge 33 静态合同失败（未完成的 starter 应当失败）。"
}

$runId = ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c33-$runId"
$workDir = Join-Path $tempRoot 'candidate'
$fixtureSource = (Resolve-Path (Join-Path $PSScriptRoot '..\fixtures')).Path
$testSource = (Resolve-Path (Join-Path $PSScriptRoot 'canonical.tftest.hcl')).Path
$workspaceTestSource = (Resolve-Path (Join-Path $PSScriptRoot 'invalid-workspace.tftest.hcl')).Path
$namePrefix = 'tfpro-c33'
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
$commonVars = @(
  "-var=localstack_endpoint=$LocalstackEndpoint",
  "-var=name_prefix=$namePrefix",
  "-var=run_id=$runId",
  '-var=catalog_file=fixtures/services.csv'
)

try {
  Copy-CleanTree $candidatePath $workDir
  Copy-Item -LiteralPath $fixtureSource -Destination (Join-Path $workDir 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $workDir 'tests-dev') | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $workDir 'tests-invalid-workspace') | Out-Null
  Copy-Item -LiteralPath $testSource -Destination (Join-Path $workDir 'tests-dev\canonical.tftest.hcl')
  Copy-Item -LiteralPath $workspaceTestSource -Destination (Join-Path $workDir 'tests-invalid-workspace\invalid-workspace.tftest.hcl')

  Invoke-Terraform $workDir @('init', '-backend=false', '-input=false', '-no-color')
  Invoke-Terraform $workDir @('workspace', 'new', 'dev')
  Invoke-ExactTerraformTest $workDir 'tests-dev' 7
  Invoke-Terraform $workDir @('workspace', 'select', 'default')
  Invoke-ExactTerraformTest $workDir 'tests-invalid-workspace' 1
  Invoke-Terraform $workDir @('workspace', 'select', 'dev')

  if ($SkipE2E) {
    Write-Host 'Challenge 33 mock/contract tests passed.'
    return
  }

  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null }
  catch { throw "LocalStack 不可用：$LocalstackEndpoint" }

  $devPlan = Join-Path $workDir 'dev-promotion.tfplan'
  Invoke-Terraform $workDir (@('plan', "-out=$devPlan", '-input=false', '-no-color') + $commonVars)

  Invoke-Terraform $workDir @('workspace', 'new', 'stage')
  $crossOutput = @(& terraform "-chdir=$workDir" apply -input=false -no-color $devPlan 2>&1)
  $crossCode = $LASTEXITCODE
  $crossOutput | Out-Host
  if ($crossCode -eq 0) { throw "dev saved plan 被错误地应用到了 stage workspace。" }
  $stageStateAfterRejectedPlan = @(& terraform "-chdir=$workDir" state list 2>$null)
  if ($LASTEXITCODE -eq 0 -and $stageStateAfterRejectedPlan.Count -ne 0) {
    throw "被拒绝的跨 workspace saved plan 仍写入了 stage state。"
  }
  $stageProbeBucket = "$namePrefix-stage-api-$runId"
  & aws --endpoint-url $LocalstackEndpoint --region us-east-1 s3api head-bucket --bucket $stageProbeBucket 2>$null
  if ($LASTEXITCODE -eq 0) { throw "跨 workspace saved plan 创建了 stage 资源。" }

  Invoke-Terraform $workDir @('workspace', 'select', 'dev')
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $devPlan)
  $devContract = Get-WorkspaceContract $workDir
  if ($devContract.workspace -ne 'dev') { throw "dev 输出合同 workspace 错误。" }

  Invoke-Terraform $workDir @('workspace', 'select', 'stage')
  Invoke-Terraform $workDir (@('apply', '-auto-approve', '-input=false', '-no-color') + $commonVars)
  $stageContract = Get-WorkspaceContract $workDir
  if ($stageContract.workspace -ne 'stage') { throw "stage 输出合同 workspace 错误。" }

  Invoke-Terraform $workDir @('workspace', 'new', 'prod')
  Invoke-Terraform $workDir (@('apply', '-auto-approve', '-input=false', '-no-color') + $commonVars)
  $prodContract = Get-WorkspaceContract $workDir
  if ($prodContract.workspace -ne 'prod') { throw "prod 输出合同 workspace 错误。" }

  foreach ($workspace in @('dev', 'stage', 'prod')) {
    Invoke-Terraform $workDir @('workspace', 'select', $workspace)
    $stateAddresses = @(& terraform "-chdir=$workDir" state list)
    if ($LASTEXITCODE -ne 0 -or $stateAddresses.Count -ne 5) { throw "$workspace state 应精确包含 5 个实例。" }
    $contract = Get-WorkspaceContract $workDir
    foreach ($service in @('api', 'worker')) {
      $bucket = "$namePrefix-$workspace-$service-$runId"
      & aws --endpoint-url $LocalstackEndpoint --region us-east-1 s3api head-bucket --bucket $bucket 2>$null
      if ($LASTEXITCODE -ne 0) { throw "$workspace bucket 不存在：$bucket" }
      $bucketWorkspaceTag = (& aws --endpoint-url $LocalstackEndpoint --region us-east-1 s3api get-bucket-tagging --bucket $bucket --query "TagSet[?Key=='Workspace'].Value | [0]" --output text)
      if ($LASTEXITCODE -ne 0 -or $bucketWorkspaceTag -ne $workspace) { throw "$bucket 的真实 Workspace tag 错误。" }
      $topicArn = $contract.topics.PSObject.Properties[$service].Value
      $expectedTopicName = "$namePrefix-$workspace-$service-$runId-events"
      if ($contract.topic_names.PSObject.Properties[$service].Value -ne $expectedTopicName) { throw "$workspace topic 名称合同错误。" }
      $topicWorkspaceTag = (& aws --endpoint-url $LocalstackEndpoint --region us-east-1 sns list-tags-for-resource --resource-arn $topicArn --query "Tags[?Key=='Workspace'].Value | [0]" --output text)
      if ($LASTEXITCODE -ne 0 -or $topicWorkspaceTag -ne $workspace) { throw "$expectedTopicName 的真实 Workspace tag 错误。" }
    }
  }

  $devBucket = "$namePrefix-dev-api-$runId"
  & aws --endpoint-url $LocalstackEndpoint --region us-east-1 s3api put-bucket-tagging --bucket $devBucket --tagging 'TagSet=[{Key=Workspace,Value=tampered},{Key=Challenge,Value=33}]' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "无法注入 dev drift。" }

  Invoke-Terraform $workDir @('workspace', 'select', 'stage')
  $stageClean = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $commonVars) @(0, 2)
  if ($stageClean -ne 0) { throw "dev drift 污染了 stage state。" }

  Invoke-Terraform $workDir @('workspace', 'select', 'dev')
  $devDrift = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $commonVars) @(0, 2)
  if ($devDrift -ne 2) { throw "dev workspace 未检测到注入的 tag drift。" }
  Invoke-Terraform $workDir (@('apply', '-auto-approve', '-input=false', '-no-color') + $commonVars)

  $reorderedVars = @(
    "-var=localstack_endpoint=$LocalstackEndpoint",
    "-var=name_prefix=$namePrefix",
    "-var=run_id=$runId",
    '-var=catalog_file=fixtures/services-reordered.csv'
  )
  $reorderedCode = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $reorderedVars) @(0, 2)
  if ($reorderedCode -ne 0) { throw "CSV 重排行产生了资源变更。" }

  foreach ($workspace in @('prod', 'stage', 'dev')) {
    Invoke-Terraform $workDir @('workspace', 'select', $workspace)
    Invoke-Terraform $workDir (@('destroy', '-auto-approve', '-input=false', '-no-color') + $commonVars)
  }
  Invoke-Terraform $workDir @('workspace', 'select', 'default')
  foreach ($workspace in @('dev', 'stage', 'prod')) {
    Invoke-Terraform $workDir @('workspace', 'delete', $workspace)
  }

  $buckets = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 s3api list-buckets --query 'Buckets[].Name' --output text)
  if (($buckets -join ' ') -match [regex]::Escape("$namePrefix-")) { throw "destroy 后仍有 Challenge 33 bucket。" }
  $topics = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 sns list-topics --query 'Topics[].TopicArn' --output text)
  if (($topics -join ' ') -match [regex]::Escape("$namePrefix-")) { throw "destroy 后仍有 Challenge 33 topic。" }

  Write-Host 'Challenge 33 passed: 8 tests + independent field failures + real resource names/tags + workspace isolation + saved-plan rejection + drift isolation + reorder + exact cleanup.'
}
finally {
  if (Test-Path $workDir) {
    $workspaceOutput = @(& terraform "-chdir=$workDir" workspace list 2>$null)
    foreach ($workspace in @('prod', 'stage', 'dev')) {
      if (($workspaceOutput -join "`n") -match "(?m)^\s*\*?\s*$workspace\s*$") {
        & terraform "-chdir=$workDir" workspace select $workspace 2>$null | Out-Null
        & terraform "-chdir=$workDir" destroy -auto-approve -input=false -no-color @commonVars 2>$null | Out-Null
      }
    }
    & terraform "-chdir=$workDir" workspace select default 2>$null | Out-Null
    foreach ($workspace in @('dev', 'stage', 'prod')) {
      & terraform "-chdir=$workDir" workspace delete -force $workspace 2>$null | Out-Null
    }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
