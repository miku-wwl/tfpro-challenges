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
  $keys = @([regex]::Matches($endpointBlock, '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  if (($keys -join ',') -ne 'ec2,iam,sts') { throw "endpoints 必须精确包含 ec2、iam、sts。" }
  foreach ($service in @('ec2', 'iam', 'sts')) {
    if (-not (Test-ExactAssignment $endpointBlock $service 'var\.localstack_endpoint')) {
      throw "$service endpoint 必须引用 var.localstack_endpoint。"
    }
  }
  if ($safe -match '(?im)(^\s*(?:profile|token|shared_config_files|shared_credentials_files|web_identity_token_file)\s*=|shared_credentials|^\s*assume_role(?:_with_web_identity)?\s*\{|AKIA[0-9A-Z]{16})') {
    throw "禁止替代凭证源、AssumeRole 或疑似真实 AWS access key。"
  }
}

function Assert-SensitiveSourceContract([string]$Source) {
  $safe = Remove-HclComments $Source
  $bootstrapBlocks = @(Get-HclBlocks $safe '(?m)^\s*variable\s+"bootstrap"\s*\{')
  if ($bootstrapBlocks.Count -ne 1 -or -not (Test-ExactAssignment $bootstrapBlocks[0] 'sensitive' 'true')) {
    throw 'bootstrap 必须是唯一的复杂 variable block，并精确设置 sensitive = true。'
  }
  $requiredBlocks = [ordered]@{
    'check\s+"identity_boundary_scoped"\s*\{' = 1
    'data\s+"aws_iam_policy_document"\s+"trust"\s*\{' = 1
    'data\s+"aws_iam_policy_document"\s+"permissions"\s*\{' = 1
    'resource\s+"aws_iam_role"\s+"workload"\s*\{' = 1
    'resource\s+"aws_iam_policy"\s+"bootstrap_read"\s*\{' = 1
    'resource\s+"aws_iam_role_policy_attachment"\s+"bootstrap_read"\s*\{' = 1
    'resource\s+"aws_iam_instance_profile"\s+"workload"\s*\{' = 1
    'resource\s+"aws_launch_template"\s+"identity"\s*\{' = 1
  }
  foreach ($entry in $requiredBlocks.GetEnumerator()) {
    if ([regex]::Matches($safe, $entry.Key).Count -ne $entry.Value) { throw "身份/敏感结构合同缺失或重复：$($entry.Key)" }
  }
  $boundaryBlocks = @(Get-HclBlocks $safe '(?m)^\s*check\s+"identity_boundary_scoped"\s*\{')
  if ($boundaryBlocks.Count -ne 1) { throw 'check.identity_boundary_scoped 必须精确出现一次。' }
  foreach ($pattern in @(
      'length\(var\.identity_boundary\.allowed_parameter_arns\)\s*>\s*0',
      'alltrue\s*\(',
      '!strcontains\(arn,\s*"\*"\)',
      'parameter/tfpro/'
    )) {
    if ($boundaryBlocks[0] -notmatch $pattern) { throw "identity boundary check 缺少实质条件：$pattern" }
  }
  if ($safe -notmatch 'permission_actions\s*=\s*\[\s*"ssm:GetParameter"\s*,\s*"ssm:GetParameters"\s*\]') {
    throw 'permission_actions 必须精确包含两个只读 SSM action。'
  }
  if ($safe -notmatch 'resources\s*=\s*sort\(tolist\(var\.identity_boundary\.allowed_parameter_arns\)\)') {
    throw 'permissions policy 必须只引用排序后的 allowed_parameter_arns。'
  }
  if ($safe -notmatch 'rendered_user_data\s*=\s*templatefile\(' -or $safe -notmatch 'user_data\s*=\s*base64encode\(local\.rendered_user_data\)') {
    throw '启动数据必须通过 templatefile 渲染，并 base64 写入 launch template。'
  }
  if ($safe -notmatch 'ignore_changes\s*=\s*\[tag_specifications\]') {
    throw '必须仅忽略 LocalStack launch-template tag_specifications 回读噪声。'
  }
  $outputBlocks = @(Get-HclBlocks $safe '(?m)^\s*output\s+"[^"]+"\s*\{')
  $outputNames = @($outputBlocks | ForEach-Object { [regex]::Match($_, 'output\s+"([^"]+)"').Groups[1].Value } | Sort-Object)
  if (($outputNames -join ',') -ne 'bootstrap_digest,identity_contract,launch_template_id') {
    throw 'outputs 必须精确是 bootstrap_digest、identity_contract、launch_template_id。'
  }
  $digestBlock = @($outputBlocks | Where-Object { $_ -match '^\s*output\s+"bootstrap_digest"' })
  if ($digestBlock.Count -ne 1 -or -not (Test-ExactAssignment $digestBlock[0] 'value' 'nonsensitive\(sha256\(local\.rendered_user_data\)\)')) {
    throw 'bootstrap_digest 必须精确输出 nonsensitive(sha256(local.rendered_user_data))。'
  }
  foreach ($block in @($outputBlocks | Where-Object { $_ -notmatch '^\s*output\s+"bootstrap_digest"' })) {
    if ($block -match '(var\.bootstrap|local\.rendered_user_data|\.user_data)') { throw '非 digest output 禁止引用敏感 payload。' }
  }
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

function Set-BootstrapTfvars([string]$Path, [string]$Token, [string]$Password) {
  $document = [ordered]@{
    bootstrap = [ordered]@{
      api_token         = $Token
      database_password = $Password
      feature_flags     = [ordered]@{ metrics = $true; tracing = $false }
    }
  }
  $document | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Decode-Base64([string]$Encoded) {
  return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Encoded))
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
$expectedBoundary = Get-Content -LiteralPath (Join-Path $labRoot 'fixtures\expected-boundary.json') -Raw | ConvertFrom-Json -Depth 20
$expectedActions = @($expectedBoundary.actions | Sort-Object)
$expectedResourcePrefix = [string]$expectedBoundary.resource_prefix
if (($expectedActions -join ',') -ne 'ssm:GetParameter,ssm:GetParameters' -or
  $expectedResourcePrefix -ne 'arn:aws:ssm:us-east-1:000000000000:parameter/tfpro/') {
  throw 'expected-boundary.json 不符合本题精确 action/namespace 合同。'
}
$source = (Get-ChildItem -LiteralPath $candidatePath -Recurse -File -Filter '*.tf' | Get-Content -Raw) -join "`n"
Assert-AwsProviderContract $source
Assert-SensitiveSourceContract $source

$suffix = ([Guid]::NewGuid().ToString('N')).Substring(0, 10)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c32-$suffix"
$workDir = Join-Path $tempRoot 'candidate'
$namePrefix = "c32-$suffix"
$runId = "run-$suffix"
$roleName = "$namePrefix-workload"
$policyName = "$namePrefix-bootstrap-read"
$templateName = "$namePrefix-identity"
$policyArn = "arn:aws:iam::000000000000:policy/tfpro/$policyName"
$originalToken = "token-$suffix-reviewed"
$originalPassword = "password-$suffix-reviewed-value"
$alternateToken = "token-$suffix-unreviewed"
$alternatePassword = "password-$suffix-unreviewed-value"
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
  Invoke-ExactTests $workDir 8

  if ($SkipE2E) {
    Write-Host 'PASS: Challenge 32 精确 8/8 canonical tests（已跳过 E2E）。'
    return
  }

  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null }
  catch { throw "LocalStack 不可用：$LocalstackEndpoint" }
  $remoteMutationStarted = $true

  Remove-Item -LiteralPath (Join-Path $workDir 'tests') -Recurse -Force
  $tfvarsPath = Join-Path $workDir 'bootstrap.auto.tfvars.json'
  Set-BootstrapTfvars $tfvarsPath $originalToken $originalPassword
  $planPath = Join-Path $workDir 'reviewed.tfplan'
  $planOutput = @(& terraform "-chdir=$workDir" plan "-out=$planPath" -input=false -no-color @commonVars 2>&1)
  $planCode = $LASTEXITCODE
  $planOutput | Out-Host
  $humanPlan = $planOutput -join "`n"
  if ($planCode -ne 0) { throw "saved plan 创建失败，exit code=$planCode。" }
  if ($humanPlan.Contains($originalToken) -or $humanPlan.Contains($originalPassword)) { throw 'human plan 泄露了 bootstrap 明文。' }
  if ($humanPlan -notmatch '\(sensitive value\)') { throw 'human plan 没有显示 sensitivity redaction。' }

  $planJson = (& terraform "-chdir=$workDir" show -json $planPath) | ConvertFrom-Json -Depth 100
  if ($LASTEXITCODE -ne 0) { throw '无法读取 saved plan JSON。' }
  $launchChange = @($planJson.resource_changes | Where-Object { $_.address -eq 'aws_launch_template.identity' })
  if ($launchChange.Count -ne 1 -or $launchChange[0].change.after_sensitive.user_data -ne $true) {
    throw 'plan JSON 必须将 launch template user_data 标记为 sensitive。'
  }
  foreach ($address in @('aws_iam_role.workload', 'aws_iam_policy.bootstrap_read', 'aws_iam_instance_profile.workload', 'aws_launch_template.identity')) {
    $taggedChange = @($planJson.resource_changes | Where-Object { $_.address -eq $address })
    if ($taggedChange.Count -ne 1) { throw "$address 必须精确出现在 saved plan。" }
    $runIdProperty = $taggedChange[0].change.after.tags.PSObject.Properties['RunId']
    if ($null -eq $runIdProperty -or $runIdProperty.Value -ne $runId) {
      throw "$address 的 saved plan 缺少精确 RunId=$runId tag。"
    }
  }
  $plannedUserData = Decode-Base64 $launchChange[0].change.after.user_data
  if (-not $plannedUserData.Contains($originalToken) -or -not $plannedUserData.Contains($originalPassword)) {
    throw 'plan JSON 应真实包含可恢复的 reviewed payload，证明该 artifact 必须受保护。'
  }
  $digestOutput = $planJson.output_changes.bootstrap_digest
  $digestSensitiveProperty = $digestOutput.PSObject.Properties['sensitive']
  if ($null -ne $digestSensitiveProperty -and $digestSensitiveProperty.Value -eq $true) {
    throw 'bootstrap_digest output 不应保留 sensitivity。'
  }

  Set-BootstrapTfvars $tfvarsPath $alternateToken $alternatePassword
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $planPath)

  $stateJson = (& terraform "-chdir=$workDir" show -json) | ConvertFrom-Json -Depth 100
  if ($LASTEXITCODE -ne 0) { throw '无法读取 state JSON。' }
  $stateLaunch = @($stateJson.values.root_module.resources | Where-Object { $_.address -eq 'aws_launch_template.identity' })
  if ($stateLaunch.Count -ne 1 -or $stateLaunch[0].sensitive_values.user_data -ne $true) {
    throw 'state JSON 必须记录 user_data 的 sensitivity metadata。'
  }
  $stateUserData = Decode-Base64 $stateLaunch[0].values.user_data
  if (-not $stateUserData.Contains($originalToken) -or -not $stateUserData.Contains($originalPassword) -or $stateUserData.Contains($alternateToken) -or $stateUserData.Contains($alternatePassword)) {
    throw 'state 没有保留 reviewed saved-plan payload，或错误使用了磁盘上的未审阅变量。'
  }

  $callerJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 sts get-caller-identity --output json 2>&1)
  if ($LASTEXITCODE -ne 0 -or (($callerJson -join "`n" | ConvertFrom-Json).Account -ne '000000000000')) { throw 'STS caller 不是 LocalStack 测试账号。' }
  $roleJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam get-role --role-name $roleName --output json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'LocalStack IAM role 不存在。' }
  $remoteRole = ($roleJson -join "`n") | ConvertFrom-Json -Depth 50
  if ($remoteRole.Role.AssumeRolePolicyDocument.Statement[0].Principal.Service -ne 'ec2.amazonaws.com' -or
    (@($remoteRole.Role.AssumeRolePolicyDocument.Statement[0].Action) -join ',') -ne 'sts:AssumeRole') {
    throw '远端 trust policy 不是精确的 EC2 AssumeRole 边界。'
  }
  $profileJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam get-instance-profile --instance-profile-name $roleName --output json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'LocalStack instance profile 不存在。' }
  $remoteProfile = ($profileJson -join "`n") | ConvertFrom-Json -Depth 50
  if (@($remoteProfile.InstanceProfile.Roles).Count -ne 1 -or $remoteProfile.InstanceProfile.Roles[0].RoleName -ne $roleName) {
    throw '远端 instance profile 必须精确绑定 workload role。'
  }
  $policyJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam get-policy --policy-arn $policyArn --output json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw 'LocalStack managed policy 不存在。' }
  $remotePolicyMetadata = ($policyJson -join "`n") | ConvertFrom-Json -Depth 50
  $templateMetadataJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-launch-templates --launch-template-names $templateName --output json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw '无法读取 LocalStack launch template metadata。' }
  $remoteTemplateMetadata = ($templateMetadataJson -join "`n") | ConvertFrom-Json -Depth 50
  Assert-RemoteRunIdTags @($remoteRole.Role) $runId 'IAM role'
  Assert-RemoteRunIdTags @($remoteProfile.InstanceProfile) $runId 'IAM instance profile'
  Assert-RemoteRunIdTags @($remotePolicyMetadata.Policy) $runId 'IAM managed policy'
  Assert-RemoteRunIdTags @($remoteTemplateMetadata.LaunchTemplates) $runId 'EC2 launch template'
  $attachmentsJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam list-attached-role-policies --role-name $roleName --output json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw '无法读取 workload role attachments。' }
  $remoteAttachments = (($attachmentsJson -join "`n") | ConvertFrom-Json -Depth 30).AttachedPolicies
  if (@($remoteAttachments).Count -ne 1 -or $remoteAttachments[0].PolicyArn -ne $policyArn -or $remoteAttachments[0].PolicyName -ne $policyName) {
    throw 'role_policy_attachment 必须把唯一的目标 policy 附到目标 workload role。'
  }
  $versionJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam get-policy-version --policy-arn $policyArn --version-id $remotePolicyMetadata.Policy.DefaultVersionId --output json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw '无法读取 LocalStack policy 默认版本。' }
  $remotePolicyVersion = ($versionJson -join "`n") | ConvertFrom-Json -Depth 50
  $remoteActions = @($remotePolicyVersion.PolicyVersion.Document.Statement[0].Action | Sort-Object)
  $remoteResources = @($remotePolicyVersion.PolicyVersion.Document.Statement[0].Resource | Sort-Object)
  $expectedResources = @("${expectedResourcePrefix}api-token", "${expectedResourcePrefix}database-password") | Sort-Object
  if (($remoteActions -join ',') -ne ($expectedActions -join ',') -or ($remoteResources -join ',') -ne ($expectedResources -join ',') -or
    @($remoteActions + $remoteResources | Where-Object { $_ -match '\*' }).Count -ne 0) {
    throw '远端 IAM policy action/resource 不是精确的无 wildcard 边界。'
  }
  $remoteTemplateJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-launch-template-versions --launch-template-name $templateName --versions '$Latest' --output json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "LocalStack launch template 不存在：$($remoteTemplateJson -join "`n")" }
  $remoteTemplate = ($remoteTemplateJson -join "`n") | ConvertFrom-Json -Depth 50
  $remoteUserData = Decode-Base64 $remoteTemplate.LaunchTemplateVersions[0].LaunchTemplateData.UserData
  if (-not $remoteUserData.Contains($originalToken) -or $remoteUserData.Contains($alternateToken) -or
    $remoteTemplate.LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile.Name -ne $roleName) {
    throw '远端 launch template 没有保存 reviewed payload。'
  }

  Set-BootstrapTfvars $tfvarsPath $originalToken $originalPassword
  $cleanCode = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $commonVars) @(0, 2)
  if ($cleanCode -ne 0) { throw 'apply reviewed plan 后必须是 clean plan。' }
  Invoke-Terraform $workDir (@('destroy', '-auto-approve', '-input=false', '-no-color') + $commonVars)

  & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-launch-templates --launch-template-names $templateName 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { throw 'destroy 后 launch template 仍存在。' }
  & aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam get-role --role-name $roleName 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { throw 'destroy 后 IAM role 仍存在。' }
  & aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam get-instance-profile --instance-profile-name $roleName 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { throw 'destroy 后 instance profile 仍存在。' }
  & aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam get-policy --policy-arn $policyArn 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { throw 'destroy 后 IAM policy 仍存在。' }

  Write-Host 'PASS: Challenge 32 精确 8/8 tests；human redaction、plan/state facts、reviewed saved-plan gate、LocalStack IAM/EC2/STS、clean plan、destroy 与零残留均通过。'
}
finally {
  if ($remoteMutationStarted -and (Test-Path $workDir) -and (Test-Path (Join-Path $workDir 'terraform.tfstate'))) {
    try {
      Set-BootstrapTfvars (Join-Path $workDir 'bootstrap.auto.tfvars.json') $originalToken $originalPassword
      & terraform "-chdir=$workDir" destroy -auto-approve -input=false -no-color @commonVars 2>$null | Out-Null
    }
    catch { Write-Warning "Terraform 兜底 destroy 失败：$($_.Exception.Message)" }
  }
  if ($remoteMutationStarted) {
    try { & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-launch-template --launch-template-name $templateName 2>$null | Out-Null } catch {}
    try { & aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam remove-role-from-instance-profile --instance-profile-name $roleName --role-name $roleName 2>$null | Out-Null } catch {}
    try { & aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam delete-instance-profile --instance-profile-name $roleName 2>$null | Out-Null } catch {}
    try { & aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam detach-role-policy --role-name $roleName --policy-arn $policyArn 2>$null | Out-Null } catch {}
    try { & aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam delete-policy --policy-arn $policyArn 2>$null | Out-Null } catch {}
    try { & aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam delete-role --role-name $roleName 2>$null | Out-Null } catch {}
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
