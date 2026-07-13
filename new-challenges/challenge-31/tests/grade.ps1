[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "..\starter"),
  [string]$LocalstackEndpoint = "http://localhost:4566",
  [switch]$SkipE2E
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-LoopbackEndpoint([string]$Endpoint) {
  $rawPattern = '\Ahttps?://(?:localhost|127\.0\.0\.1|\[::1\])(?::[0-9]{1,5})?/?\z'
  if (-not [regex]::IsMatch($Endpoint, $rawPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase) -or $Endpoint.Contains('\')) {
    throw "LocalstackEndpoint 必须是无 userinfo/path/query/fragment 的原始 loopback HTTP(S) 根地址。"
  }
  $uri = $null
  if (-not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri)) {
    throw "LocalstackEndpoint 必须是绝对 URI。"
  }
  $hostName = $uri.Host.Trim('[', ']').ToLowerInvariant()
  if ($uri.Scheme -notin @("http", "https") -or
    $hostName -notin @("localhost", "127.0.0.1", "::1") -or
    -not [string]::IsNullOrEmpty($uri.UserInfo) -or
    $uri.AbsolutePath -ne "/" -or
    -not [string]::IsNullOrEmpty($uri.Query) -or
    -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw "LocalstackEndpoint 仅允许 loopback HTTP(S) 根地址。"
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
  $blocks = [Collections.Generic.List[string]]::new()
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

function Test-ExactAssignment([string]$Block, [string]$Name, [string]$ValuePattern) {
  $escapedName = [regex]::Escape($Name)
  $allAssignments = [regex]::Matches($Block, "(?m)^\s*$escapedName\s*=")
  $exactAssignments = [regex]::Matches($Block, "(?m)^\s*$escapedName\s*=\s*$ValuePattern\s*$")
  return $allAssignments.Count -eq 1 -and $exactAssignments.Count -eq 1
}

function Assert-AwsProviderContract([string]$Source) {
  $safe = Remove-HclComments $Source
  $endpointVariables = @(Get-HclBlocks $safe '(?m)^\s*variable\s+"localstack_endpoint"\s*\{')
  if ($endpointVariables.Count -ne 1 -or -not (Test-ExactAssignment $endpointVariables[0] 'default' '"http://localhost:4566"')) {
    throw 'localstack_endpoint variable 必须唯一，且默认值精确为 http://localhost:4566。'
  }
  $blocks = @(Get-HclBlocks $safe '(?m)^\s*provider\s+"aws"\s*\{')
  if ($blocks.Count -ne 1) { throw "必须且只能有一个顶层 aws provider block。" }
  $block = $blocks[0]
  $required = [ordered]@{
    region                       = 'var\.aws_region'
    access_key                   = '"test"'
    secret_key                   = '"test"'
    skip_credentials_validation = 'true'
    skip_metadata_api_check      = 'true'
    skip_requesting_account_id   = 'true'
  }
  foreach ($entry in $required.GetEnumerator()) {
    if (-not (Test-ExactAssignment $block $entry.Key $entry.Value)) {
      throw "AWS provider 必须精确设置 $($entry.Key)；凭证只能是字面量 test/test。"
    }
  }
  $endpointBlocks = @(Get-HclBlocks $block '(?m)^\s*endpoints\s*\{')
  if ($endpointBlocks.Count -ne 1) { throw "AWS provider 必须且只能有一个 endpoints block。" }
  $endpointBlock = $endpointBlocks[0]
  $endpointKeys = @([regex]::Matches($endpointBlock, '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  if (($endpointKeys -join ',') -ne 'ec2,sts') { throw "endpoints 必须精确包含 ec2、sts。" }
  foreach ($service in @('ec2', 'sts')) {
    if (-not (Test-ExactAssignment $endpointBlock $service 'var\.localstack_endpoint')) {
      throw "$service endpoint 必须引用 var.localstack_endpoint。"
    }
  }
  if ($safe -match '(?im)(aws_autoscaling_group|^\s*autoscaling\s*=|^\s*(?:profile|token|shared_config_files|shared_credentials_files|web_identity_token_file)\s*=|shared_credentials|^\s*assume_role(?:_with_web_identity)?\s*\{|AKIA[0-9A-Z]{16})') {
    throw "禁止 Auto Scaling、替代凭证源、AssumeRole 或疑似真实 AWS access key。"
  }
}

function Assert-SourceContract([string]$Source) {
  $safe = Remove-HclComments $Source
  $requiredBlocks = [ordered]@{
    'check\s+"fleet_ids_unique"\s*\{'       = 1
    'check\s+"fleet_capacity_bounds"\s*\{' = 1
    'check\s+"fleet_subnets_exist"\s*\{'    = 1
    'check\s+"fleet_fields_valid"\s*\{'     = 1
    'data\s+"aws_ami"\s+"selected"\s*\{'   = 1
    'data\s+"aws_vpc"\s+"managed"\s*\{'    = 1
    'data\s+"aws_subnet"\s+"managed"\s*\{' = 1
    'resource\s+"aws_launch_template"\s+"fleet"\s*\{' = 1
    'resource\s+"aws_instance"\s+"fleet"\s*\{' = 1
  }
  foreach ($entry in $requiredBlocks.GetEnumerator()) {
    if ([regex]::Matches($safe, $entry.Key).Count -ne $entry.Value) { throw "结构合同缺失或重复：$($entry.Key)" }
  }
  $checkPatterns = [ordered]@{
    fleet_ids_unique = @(
      'alltrue\s*\(',
      'values\(local\.fleet_groups\)',
      'length\(group\)\s*==\s*1'
    )
    fleet_capacity_bounds = @(
      'fleet\.min_size\s*>=\s*0',
      'fleet\.min_size\s*<=\s*fleet\.desired_capacity',
      'fleet\.desired_capacity\s*<=\s*fleet\.max_size',
      'floor\(fleet\.desired_capacity\)\s*==\s*fleet\.desired_capacity'
    )
    fleet_subnets_exist = @(
      'alltrue\s*\(',
      'contains\(keys\(var\.network\.subnets\),\s*fleet\.subnet_key\)'
    )
    fleet_fields_valid = @(
      'contains\(\["true",\s*"false"\],\s*fleet\.enabled_text\)',
      'fleet\.fleet_id\s*!=\s*""',
      'fleet\.instance_type\s*!=\s*""',
      'fleet\.owner\s*!=\s*""'
    )
  }
  foreach ($entry in $checkPatterns.GetEnumerator()) {
    $blocks = @(Get-HclBlocks $safe "(?m)^\s*check\s+`"$($entry.Key)`"\s*\{")
    if ($blocks.Count -ne 1) { throw "check.$($entry.Key) 必须精确出现一次。" }
    foreach ($pattern in $entry.Value) {
      if ($blocks[0] -notmatch $pattern) { throw "check.$($entry.Key) 缺少实质条件：$pattern" }
    }
  }
  $networkBlocks = @(Get-HclBlocks $safe '(?m)^\s*variable\s+"network"\s*\{')
  if ($networkBlocks.Count -ne 1) { throw 'variable.network 必须精确出现一次。' }
  foreach ($pattern in @(
      'can\(cidrnetmask\(var\.network\.cidr_block\)\)',
      'length\(var\.network\.subnets\)\s*>\s*0',
      'can\(cidrnetmask\(subnet\.cidr_block\)\)',
      'trimspace\(subnet\.owner\)\s*!=\s*""',
      'trimspace\(subnet\.availability_zone\)\s*!=\s*""',
      'length\(distinct\(\[for\s+subnet\s+in\s+values\(var\.network\.subnets\)\s*:\s*subnet\.cidr_block\]\)\)\s*==\s*length\(var\.network\.subnets\)'
    )) {
    if ($networkBlocks[0] -notmatch $pattern) { throw "network validation 缺少实质条件：$pattern" }
  }
  if ($safe -notmatch '(?s)active_fleets\s*=.*?fleet\.environment\s*==\s*var\.environment\s*&&\s*fleet\.enabled') {
    throw "active_fleets 必须同时按 environment 与 enabled 过滤。"
  }
  if ($safe -notmatch 'for_each\s*=\s*local\.instances_by_key' -or $safe -notmatch 'for_each\s*=\s*local\.deployable_fleets_by_id') {
    throw "launch template/instance 必须使用稳定的 for_each collection。"
  }
  if ($safe -notmatch 'ignore_changes\s*=\s*\[launch_template\]' -or $safe -notmatch 'replace_triggered_by\s*=\s*\[terraform_data\.template_revision\[each\.key\]\]') {
    throw "必须窄范围处理 LocalStack launch_template 回读差异，并保留模板变更替换语义。"
  }
  if ($safe -notmatch 'ignore_changes\s*=\s*\[tag_specifications\]' -or $safe -notmatch 'triggers_replace\s*=\s*\[aws_launch_template\.fleet\[each\.value\.fleet_id\]\.latest_version\]') {
    throw "launch template 忽略范围和 revision sentinel 触发源不精确。"
  }
  if ([regex]::Matches($safe, 'resource\s+"terraform_data"\s+"template_revision"\s*\{').Count -ne 1) {
    throw "必须且只能有一个 terraform_data.template_revision sentinel。"
  }
  if ($safe -match '(?m)^\s*count\s*=') { throw "本题禁止用 count 形成资源身份。" }
}

function Copy-CleanTree([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Where-Object { $_.Name -notin @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
  }
  Get-ChildItem -LiteralPath $Destination -Recurse -Force | Where-Object {
    $_.Name -eq '.terraform' -or $_.Name -in @('terraform.tfstate', 'terraform.tfstate.backup') -or $_.Extension -eq '.tfplan'
  } | Sort-Object FullName -Descending | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-Terraform([string]$Directory, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0)) {
  & terraform "-chdir=$Directory" @Arguments | Out-Host
  $code = $LASTEXITCODE
  if ($code -notin $AllowedExitCodes) { throw "terraform $($Arguments -join ' ') 失败，exit code=$code" }
  return $code
}

function Invoke-ExactTests([string]$Directory, [int]$ExpectedPassed) {
  $output = @(& terraform "-chdir=$Directory" test -test-directory=tests -no-color 2>&1)
  $code = $LASTEXITCODE
  $output | Out-Host
  $text = $output -join "`n"
  $summaries = [regex]::Matches($text, '(?m)^Success!\s+([0-9]+) passed,\s+0 failed\.\s*$')
  $passes = [regex]::Matches($text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$')
  if ($code -ne 0 -or $summaries.Count -ne 1 -or [int]$summaries[0].Groups[1].Value -ne $ExpectedPassed -or $passes.Count -ne $ExpectedPassed) {
    throw "canonical tests 必须精确通过 $ExpectedPassed/$ExpectedPassed；exit code=$code。"
  }
}

function Invoke-AwsJson([string[]]$Arguments) {
  $json = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 @Arguments --output json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "aws $($Arguments -join ' ') 失败：$($json -join "`n")" }
  return (($json -join "`n") | ConvertFrom-Json -Depth 100)
}

function Assert-RemoteRunIdTags([object[]]$Resources, [string]$ExpectedRunId, [string]$Label) {
  foreach ($resource in @($Resources)) {
    $matches = @($resource.Tags | Where-Object { $_.Key -eq 'RunId' })
    if ($matches.Count -ne 1 -or $matches[0].Value -ne $ExpectedRunId) {
      throw "$Label 每个远端资源必须且只能有一个 RunId=$ExpectedRunId tag。"
    }
  }
}

Assert-LoopbackEndpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source = (Get-ChildItem -LiteralPath $candidatePath -Recurse -File -Filter '*.tf' | Get-Content -Raw) -join "`n"
Assert-AwsProviderContract $source
Assert-SourceContract $source

$suffix = ([Guid]::NewGuid().ToString('N')).Substring(0, 10)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c31-$suffix"
$workDir = Join-Path $tempRoot 'candidate'
$namePrefix = "c31-$suffix"
$runId = "run-$suffix"
$commonVars = @("-var=name_prefix=$namePrefix", "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
$remoteMutationStarted = $false

try {
  Copy-CleanTree $candidatePath $workDir
  Copy-Item -LiteralPath (Join-Path $labRoot 'fixtures') -Destination (Join-Path $tempRoot 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $workDir 'tests') | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $workDir 'tests\canonical.tftest.hcl') -Force

  Invoke-Terraform $workDir @('fmt', '-check', '-recursive')
  Invoke-Terraform $workDir @('init', '-backend=false', '-input=false', '-no-color')
  Invoke-Terraform $workDir @('validate', '-no-color')
  Invoke-ExactTests $workDir 11

  if ($SkipE2E) {
    Write-Host 'PASS: Challenge 31 精确 11/11 canonical tests（已跳过 E2E）。'
    return
  }

  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null }
  catch { throw "LocalStack 不可用：$LocalstackEndpoint" }
  $remoteMutationStarted = $true

  Remove-Item -LiteralPath (Join-Path $workDir 'tests') -Recurse -Force
  $planPath = Join-Path $workDir 'reviewed.tfplan'
  Invoke-Terraform $workDir (@('plan', "-out=$planPath", '-input=false', '-no-color') + $commonVars)
  $planJson = (& terraform "-chdir=$workDir" show -json $planPath) | ConvertFrom-Json -Depth 100
  if ($LASTEXITCODE -ne 0) { throw '无法读取 saved plan JSON。' }
  $changes = @($planJson.resource_changes | Where-Object { $_.mode -eq 'managed' })
  $expectedAddresses = @(
    'aws_vpc.this',
    'aws_subnet.this["private-a"]', 'aws_subnet.this["public-a"]',
    'aws_security_group.fleet["api"]', 'aws_security_group.fleet["worker"]',
    'aws_launch_template.fleet["api"]', 'aws_launch_template.fleet["worker"]',
    'aws_instance.fleet["api/01"]', 'aws_instance.fleet["api/02"]', 'aws_instance.fleet["worker/01"]',
    'terraform_data.template_revision["api/01"]', 'terraform_data.template_revision["api/02"]', 'terraform_data.template_revision["worker/01"]'
  ) | Sort-Object
  $actualAddresses = @($changes | ForEach-Object { [string]$_.address } | Sort-Object)
  if (($actualAddresses -join ',') -ne ($expectedAddresses -join ',')) {
    throw "真实 plan resource graph 不精确：$($actualAddresses -join ', ')"
  }
  if (@($changes | Where-Object { (@($_.change.actions) -join ',') -ne 'create' }).Count -ne 0) {
    throw '首次 saved plan 必须只包含 create actions。'
  }
  $launchChanges = @($changes | Where-Object { $_.type -eq 'aws_launch_template' })
  $selectedAmiId = if ($launchChanges.Count -gt 0) { [string]$launchChanges[0].change.after.image_id } else { '' }
  if ($launchChanges.Count -ne 2 -or [string]::IsNullOrWhiteSpace($selectedAmiId) -or
    @($launchChanges | Where-Object { $_.change.after.image_id -ne $selectedAmiId }).Count -ne 0) {
    throw '每个 launch template 的 image_id 必须等于 data.aws_ami.selected.id。'
  }
  $awsPlanChanges = @($changes | Where-Object { $_.type -like 'aws_*' })
  foreach ($change in $awsPlanChanges) {
    $tagProperty = $change.change.after.tags.PSObject.Properties['RunId']
    if ($null -eq $tagProperty -or $tagProperty.Value -ne $runId) {
      throw "$($change.address) 的 saved plan 缺少精确 RunId=$runId tag。"
    }
  }
  $configurationResources = @($planJson.configuration.root_module.resources)
  $launchConfig = @($configurationResources | Where-Object { $_.address -eq 'aws_launch_template.fleet' })
  $instanceConfig = @($configurationResources | Where-Object { $_.address -eq 'aws_instance.fleet' })
  if ($launchConfig.Count -ne 1 -or $instanceConfig.Count -ne 1) { throw 'plan configuration 必须各含一个 launch template/instance resource block。' }
  if (@($launchConfig[0].expressions.image_id.references) -notcontains 'data.aws_ami.selected.id' -or
    @($launchConfig[0].expressions.vpc_security_group_ids.references | Where-Object { $_ -like 'aws_security_group.fleet*' }).Count -eq 0) {
    throw 'launch template plan/config 必须引用 selected AMI 与对应 fleet SG。'
  }
  if (@($instanceConfig[0].expressions.subnet_id.references | Where-Object { $_ -like 'data.aws_subnet.managed*' }).Count -eq 0) {
    throw 'instance plan/config 必须引用 matching managed subnet。'
  }
  $instanceLaunchBlocks = @($instanceConfig[0].expressions.launch_template)
  if ($instanceLaunchBlocks.Count -ne 1 -or
    @($instanceLaunchBlocks[0].id.references | Where-Object { $_ -like 'aws_launch_template.fleet*' }).Count -eq 0 -or
    $instanceLaunchBlocks[0].version.constant_value -ne '$Latest') {
    throw 'instance plan/config 必须引用对应 launch template 的 $Latest。'
  }
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $planPath)

  $fleetIds = (& terraform "-chdir=$workDir" output -json active_fleet_ids) | ConvertFrom-Json
  if (($fleetIds -join ',') -ne 'api,worker') { throw '真实 output fleet IDs 不匹配。' }
  $fleetContract = (& terraform "-chdir=$workDir" output -json fleet_contract) | ConvertFrom-Json -Depth 30
  if ($LASTEXITCODE -ne 0 -or $fleetContract.ami_id -ne $selectedAmiId) {
    throw 'fleet contract 的 selected AMI 与 saved plan launch templates 不一致。'
  }

  $caller = Invoke-AwsJson @('sts', 'get-caller-identity')
  if ($caller.Account -ne '000000000000') { throw 'STS caller 不是 LocalStack 测试账号。' }
  $vpcs = Invoke-AwsJson @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$runId")
  $subnets = Invoke-AwsJson @('ec2', 'describe-subnets', '--filters', "Name=tag:RunId,Values=$runId")
  $groups = Invoke-AwsJson @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId")
  $templates = Invoke-AwsJson @('ec2', 'describe-launch-templates', '--filters', "Name=tag:RunId,Values=$runId")
  $instances = Invoke-AwsJson @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped')
  $instanceCount = @($instances.Reservations | ForEach-Object { @($_.Instances) }).Count
  if (@($vpcs.Vpcs).Count -ne 1 -or @($subnets.Subnets).Count -ne 2 -or @($groups.SecurityGroups).Count -ne 2 -or @($templates.LaunchTemplates).Count -ne 2 -or $instanceCount -ne 3) {
    throw "LocalStack 资源计数错误：VPC=$(@($vpcs.Vpcs).Count), subnet=$(@($subnets.Subnets).Count), SG=$(@($groups.SecurityGroups).Count), LT=$(@($templates.LaunchTemplates).Count), instance=$instanceCount"
  }
  Assert-RemoteRunIdTags @($vpcs.Vpcs) $runId 'VPC'
  Assert-RemoteRunIdTags @($subnets.Subnets) $runId 'subnet'
  Assert-RemoteRunIdTags @($groups.SecurityGroups) $runId 'security group'
  Assert-RemoteRunIdTags @($templates.LaunchTemplates) $runId 'launch template'
  $allInstances = @($instances.Reservations | ForEach-Object { @($_.Instances) })
  Assert-RemoteRunIdTags $allInstances $runId 'EC2 instance'
  $apiInstances = @($allInstances | Where-Object { @($_.Tags | Where-Object { $_.Key -eq 'FleetId' -and $_.Value -eq 'api' }).Count -eq 1 })
  $workerInstances = @($allInstances | Where-Object { @($_.Tags | Where-Object { $_.Key -eq 'FleetId' -and $_.Value -eq 'worker' }).Count -eq 1 })
  if ($apiInstances.Count -ne 2 -or $workerInstances.Count -ne 1) { throw '远端实例没有按 desired_capacity 和 FleetId 正确展开。' }
  $apiTemplate = Invoke-AwsJson @('ec2', 'describe-launch-template-versions', '--launch-template-name', "$namePrefix-api", '--versions', '$Latest')
  $workerTemplate = Invoke-AwsJson @('ec2', 'describe-launch-template-versions', '--launch-template-name', "$namePrefix-worker", '--versions', '$Latest')
  $apiGroup = @($groups.SecurityGroups | Where-Object { @($_.Tags | Where-Object { $_.Key -eq 'FleetId' -and $_.Value -eq 'api' }).Count -eq 1 })
  $workerGroup = @($groups.SecurityGroups | Where-Object { @($_.Tags | Where-Object { $_.Key -eq 'FleetId' -and $_.Value -eq 'worker' }).Count -eq 1 })
  $publicSubnet = @($subnets.Subnets | Where-Object { @($_.Tags | Where-Object { $_.Key -eq 'Name' -and $_.Value -eq "$namePrefix-public-a" }).Count -eq 1 })
  $privateSubnet = @($subnets.Subnets | Where-Object { @($_.Tags | Where-Object { $_.Key -eq 'Name' -and $_.Value -eq "$namePrefix-private-a" }).Count -eq 1 })
  if ($apiGroup.Count -ne 1 -or $workerGroup.Count -ne 1 -or $publicSubnet.Count -ne 1 -or $privateSubnet.Count -ne 1) {
    throw '无法按 stable fleet/subnet key 唯一解析远端 SG 或 subnet。'
  }
  if ($apiTemplate.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType -ne 't3.micro' -or
    $workerTemplate.LaunchTemplateVersions[0].LaunchTemplateData.InstanceType -ne 't3.small' -or
    $apiTemplate.LaunchTemplateVersions[0].LaunchTemplateData.ImageId -ne $selectedAmiId -or
    $workerTemplate.LaunchTemplateVersions[0].LaunchTemplateData.ImageId -ne $selectedAmiId -or
    (@($apiTemplate.LaunchTemplateVersions[0].LaunchTemplateData.SecurityGroupIds) -join ',') -ne $apiGroup[0].GroupId -or
    (@($workerTemplate.LaunchTemplateVersions[0].LaunchTemplateData.SecurityGroupIds) -join ',') -ne $workerGroup[0].GroupId -or
    $apiTemplate.LaunchTemplateVersions[0].LaunchTemplateData.MetadataOptions.HttpTokens -ne 'required' -or
    $workerTemplate.LaunchTemplateVersions[0].LaunchTemplateData.MetadataOptions.HttpTokens -ne 'required') {
    throw '远端 launch template 的 instance type 或 IMDSv2 合同不匹配。'
  }
  foreach ($instance in $apiInstances) {
    if ($instance.SubnetId -ne $publicSubnet[0].SubnetId) {
      throw 'api instance 没有位于 matching public-a subnet。'
    }
  }
  foreach ($instance in $workerInstances) {
    if ($instance.SubnetId -ne $privateSubnet[0].SubnetId) {
      throw 'worker instance 没有位于 matching private-a subnet。'
    }
  }

  $reorderedCode = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color', '-var=fleet_csv_path=../fixtures/fleets-reordered.csv') + $commonVars) @(0, 2)
  if ($reorderedCode -ne 0) { throw '真实 state 上重排 CSV 必须是零变更 plan。' }
  $cleanCode = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $commonVars) @(0, 2)
  if ($cleanCode -ne 0) { throw 'apply 后必须是 clean plan。' }
  Invoke-Terraform $workDir (@('destroy', '-auto-approve', '-input=false', '-no-color') + $commonVars)

  $remainingInstances = Invoke-AwsJson @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped')
  $remainingTemplates = Invoke-AwsJson @('ec2', 'describe-launch-templates', '--filters', "Name=tag:RunId,Values=$runId")
  $remainingVpcs = Invoke-AwsJson @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$runId")
  if (@($remainingInstances.Reservations).Count -ne 0 -or @($remainingTemplates.LaunchTemplates).Count -ne 0 -or @($remainingVpcs.Vpcs).Count -ne 0) {
    throw 'destroy 后仍有 Challenge 31 远端资源。'
  }
  Write-Host 'PASS: Challenge 31 精确 11/11 tests；LocalStack 1 VPC + 2 subnet + 2 SG + 2 launch template + 3 EC2 instances，saved plan、clean plan、destroy、STS 与零残留均通过。'
}
finally {
  if ($remoteMutationStarted -and (Test-Path $workDir) -and (Test-Path (Join-Path $workDir 'terraform.tfstate'))) {
    try { & terraform "-chdir=$workDir" destroy -auto-approve -input=false -no-color @commonVars 2>$null | Out-Null }
    catch { Write-Warning "Terraform 兜底 destroy 失败：$($_.Exception.Message)" }
  }
  if ($remoteMutationStarted) {
    try {
    $instanceJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-instances --filters "Name=tag:RunId,Values=$runId" 'Name=instance-state-name,Values=pending,running,stopping,stopped' --output json 2>$null)
    if ($LASTEXITCODE -eq 0) {
      $ids = @(($instanceJson -join "`n" | ConvertFrom-Json -Depth 50).Reservations | ForEach-Object { @($_.Instances).InstanceId })
      if ($ids.Count -gt 0) { & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 terminate-instances --instance-ids @ids 2>$null | Out-Null }
      if ($ids.Count -gt 0) { & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 wait instance-terminated --instance-ids @ids 2>$null | Out-Null }
    }
    }
    catch { Write-Warning "EC2 兜底清理失败：$($_.Exception.Message)" }
    try {
    $templates = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-launch-templates --filters "Name=tag:RunId,Values=$runId" --output json 2>$null)
    if ($LASTEXITCODE -eq 0) {
      foreach ($id in @(($templates -join "`n" | ConvertFrom-Json -Depth 30).LaunchTemplates | ForEach-Object { $_.LaunchTemplateId })) {
        & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-launch-template --launch-template-id $id 2>$null | Out-Null
      }
    }
    $groups = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-security-groups --filters "Name=tag:RunId,Values=$runId" --output json 2>$null)
    if ($LASTEXITCODE -eq 0) {
      foreach ($id in @(($groups -join "`n" | ConvertFrom-Json -Depth 30).SecurityGroups | ForEach-Object { $_.GroupId })) {
        & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-security-group --group-id $id 2>$null | Out-Null
      }
    }
    $subnets = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-subnets --filters "Name=tag:RunId,Values=$runId" --output json 2>$null)
    if ($LASTEXITCODE -eq 0) {
      foreach ($id in @(($subnets -join "`n" | ConvertFrom-Json -Depth 30).Subnets | ForEach-Object { $_.SubnetId })) {
        & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $id 2>$null | Out-Null
      }
    }
    $vpcs = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-vpcs --filters "Name=tag:RunId,Values=$runId" --output json 2>$null)
    if ($LASTEXITCODE -eq 0) {
      foreach ($id in @(($vpcs -join "`n" | ConvertFrom-Json -Depth 30).Vpcs | ForEach-Object { $_.VpcId })) {
        & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $id 2>$null | Out-Null
      }
    }
    }
    catch { Write-Warning "网络与 launch template 兜底清理失败：$($_.Exception.Message)" }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
