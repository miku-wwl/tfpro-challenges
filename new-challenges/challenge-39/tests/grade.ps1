[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "..\starter"),
  [string]$LocalstackEndpoint = "http://localhost:4566",
  [switch]$SkipE2E
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-LoopbackEndpoint([string]$Endpoint) {
  if ($Endpoint.Contains("`r") -or $Endpoint.Contains("`n")) { throw "LocalstackEndpoint 禁止包含 CR/LF。" }
  if ($Endpoint -notmatch '\Ahttps?://(?:localhost|127\.0\.0\.1|\[::1\]):(?:[1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])\z') { throw "LocalstackEndpoint 必须是带显式有效端口的纯 loopback HTTP(S) origin。" }
  try { $uri = [Uri]$Endpoint } catch { throw "LocalStack endpoint 不是合法 URI。" }
  if ($uri.Scheme -notin @('http', 'https') -or $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or
    $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535 -or
    $Endpoint -match '(?i)%2e|%2f|%5c|\\') { throw "拒绝 endpoint 归一化绕过。" }
}

function Remove-HclComments([string]$Text) {
  $b = [Text.StringBuilder]::new($Text.Length); $state = 'code'
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $c = $Text[$i]; $n = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
    if ($state -eq 'code') {
      if ($c -eq '"') { [void]$b.Append($c); $state = 'string' }
      elseif ($c -eq '#') { [void]$b.Append(' '); $state = 'line' }
      elseif ($c -eq '/' -and $n -eq '/') { [void]$b.Append('  '); $i++; $state = 'line' }
      elseif ($c -eq '/' -and $n -eq '*') { [void]$b.Append('  '); $i++; $state = 'block' }
      else { [void]$b.Append($c) }
    } elseif ($state -eq 'string') {
      [void]$b.Append($c); if ($c -eq '\' -and $i + 1 -lt $Text.Length) { $i++; [void]$b.Append($Text[$i]) } elseif ($c -eq '"') { $state = 'code' }
    } elseif ($state -eq 'line') {
      if ($c -eq "`n") { [void]$b.Append($c); $state = 'code' } else { [void]$b.Append(' ') }
    } else {
      if ($c -eq '*' -and $n -eq '/') { [void]$b.Append('  '); $i++; $state = 'code' } elseif ($c -eq "`n") { [void]$b.Append($c) } else { [void]$b.Append(' ') }
    }
  }
  $b.ToString()
}

function Test-HclHeredocOpener([string]$Text) {
  $contexts = [Collections.Generic.List[object]]::new()
  [void]$contexts.Add([pscustomobject]@{ Kind = 'code'; Depth = 0 })
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $current = $Text[$i]
    $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
    $nextNext = if ($i + 2 -lt $Text.Length) { $Text[$i + 2] } else { [char]0 }
    $context = $contexts[$contexts.Count - 1]

    if ($context.Kind -eq 'string') {
      if ($current -eq '\') { $i++; continue }
      if (($current -eq '$' -or $current -eq '%') -and $next -eq $current -and $nextNext -eq '{') { $i += 2; continue }
      if (($current -eq '$' -or $current -eq '%') -and $next -eq '{') {
        [void]$contexts.Add([pscustomobject]@{ Kind = 'template'; Depth = 1 }); $i++; continue
      }
      if ($current -eq '"') { $contexts.RemoveAt($contexts.Count - 1) }
      continue
    }

    if ($current -eq '"') { [void]$contexts.Add([pscustomobject]@{ Kind = 'string'; Depth = 0 }); continue }
    if ($current -eq '<' -and $next -eq '<') {
      $marker = $i + 2
      if ($marker -lt $Text.Length -and $Text[$marker] -eq '-') { $marker++ }
      while ($marker -lt $Text.Length -and $Text[$marker] -in @(' ', "`t")) { $marker++ }
      if ($marker -lt $Text.Length -and ([char]::IsLetter($Text[$marker]) -or $Text[$marker] -eq '_')) { return $true }
    }
    if ($context.Kind -eq 'template') {
      if ($current -eq '{') { $context.Depth++ }
      elseif ($current -eq '}') {
        $context.Depth--
        if ($context.Depth -eq 0) { $contexts.RemoveAt($contexts.Count - 1) }
      }
    }
  }
  return $false
}

function Get-HclBlocks([string]$Text, [string]$HeaderPattern) {
  $blocks = [Collections.Generic.List[string]]::new()
  foreach ($m in [regex]::Matches($Text, $HeaderPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    $open = $Text.IndexOf('{', $m.Index); if ($open -lt 0) { continue }; $depth = 0; $inString = $false
    for ($i = $open; $i -lt $Text.Length; $i++) {
      $c = $Text[$i]
      if ($inString) { if ($c -eq '\') { $i++; continue }; if ($c -eq '"') { $inString = $false }; continue }
      if ($c -eq '"') { $inString = $true; continue }; if ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $blocks.Add($Text.Substring($m.Index, $i - $m.Index + 1)); break } }
    }
  }
  return @($blocks)
}

function One([string]$Text, [string]$Pattern, [string]$Context) {
  $blocks = @(Get-HclBlocks $Text $Pattern); if ($blocks.Count -ne 1) { throw "$Context 必须精确出现一次。" }; $blocks[0]
}

function Assignment([string]$Block, [string]$Name, [string]$Pattern, [string]$Context) {
  if ([regex]::Matches($Block, "(?m)^\s*$([regex]::Escape($Name))\s*=\s*$Pattern\s*$").Count -ne 1) { throw "$Context 必须精确设置 $Name。" }
}

function Assert-ExactNamedBlocks([string]$Text, [string]$Pattern, [string[]]$Expected, [string]$Context) {
  $actual = @([regex]::Matches($Text, $Pattern) | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  $wanted = @($Expected | Sort-Object)
  if (($actual -join ',') -ne ($wanted -join ',')) { throw "$Context block 集合错误；expected=$($wanted -join ','), actual=$($actual -join ',')" }
}

function Assert-ExactAddressedBlocks([string]$Text, [string]$Pattern, [string[]]$Expected, [string]$Context) {
  $actual = @([regex]::Matches($Text, $Pattern) | ForEach-Object { "$($_.Groups[1].Value).$($_.Groups[2].Value)" } | Sort-Object)
  $wanted = @($Expected | Sort-Object)
  if (($actual -join ',') -ne ($wanted -join ',')) { throw "$Context address 集合错误；expected=$($wanted -join ','), actual=$($actual -join ',')" }
}

function Get-ConditionExpression([string]$Block, [string]$Context) {
  if ([regex]::Matches($Block, '(?m)^\s*condition\s*=').Count -ne 1) { throw "$Context 必须且只能声明一个 condition。" }
  $match = [regex]::Match($Block, '(?ms)^\s*condition\s*=\s*(.*?)^\s*error_message\s*=')
  if (-not $match.Success) { throw "$Context condition/error_message 结构不可审计。" }
  return $match.Groups[1].Value.Trim()
}

function Assert-Provider([string]$Text, [string]$Context) {
  $blocks = @(Get-HclBlocks $Text '(?m)^\s*provider\s+"aws"\s*\{'); if ($blocks.Count -ne 1) { throw "$Context 必须只有一个 AWS provider。" }; $p = $blocks[0]
  Assignment $p 'region' 'var\.aws_region' $Context; Assignment $p 'access_key' '"test"' $Context; Assignment $p 'secret_key' '"test"' $Context
  foreach ($flag in @('skip_credentials_validation', 'skip_metadata_api_check', 'skip_requesting_account_id')) { Assignment $p $flag 'true' $Context }
  Assignment $p 's3_use_path_style' 'true' $Context
  $ep = One $p '(?m)^\s*endpoints\s*\{' "$Context endpoints"; $keys = @([regex]::Matches($ep, '(?m)^\s*([a-z0-9_]+)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  if (($keys -join ',') -ne 'dynamodb,s3,sts') { throw "$Context endpoints 必须精确为 dynamodb,s3,sts。" }
  foreach ($s in @('dynamodb', 's3', 'sts')) { Assignment $ep $s 'var\.localstack_endpoint' "$Context endpoints" }
}

function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Where-Object { $_.Name -notin @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup', '.terraform.tfstate.lock.info') -and $_.Extension -ne '.tfplan' -and $_.Name -notlike 'tests-generated*' } | ForEach-Object {
    $target = Join-Path $Destination $_.Name
    if ($_.PSIsContainer) { Copy-Clean $_.FullName $target } else { Copy-Item -LiteralPath $_.FullName -Destination $target -Force }
  }
}

function Tf([string]$Dir, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  $out = @(& terraform "-chdir=$Dir" @Arguments 2>&1); $code = $LASTEXITCODE; $out | Out-Host
  if ($code -notin $Allowed) { throw "terraform $($Arguments -join ' ') 失败，exit=$code" }; @{ Code = $code; Text = ($out -join "`n") }
}

function ExactTests([string]$Dir, [int]$Expected) {
  $r = Tf $Dir @('test', '-test-directory=tests-generated', '-no-color')
  if ([regex]::Matches($r.Text, "(?m)^Success!\s+$Expected passed,\s+0 failed\.\s*$").Count -ne 1 -or [regex]::Matches($r.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne $Expected) { throw "必须精确通过 $Expected canonical runs。" }
}

function Assert-ExactManagedPlan([string]$Dir, [string]$PlanPath, [Collections.IDictionary]$Expected, [string]$Context) {
  $raw = @(& terraform "-chdir=$Dir" show -json $PlanPath 2>&1); $code = $LASTEXITCODE
  if ($code -ne 0) { throw "$Context 无法读取 saved-plan JSON，exit=$code：$($raw -join ' ')" }
  try { $plan = ($raw -join "`n") | ConvertFrom-Json -Depth 100 } catch { throw "$Context saved-plan JSON 无法解析：$_" }
  $managed = @($plan.resource_changes | Where-Object { $_.mode -eq 'managed' })
  if ($managed.Count -ne $Expected.Count) { throw "$Context 必须精确包含 $($Expected.Count) 个 managed changes，实际为 $($managed.Count)。" }
  foreach ($change in $managed) {
    if (-not $Expected.Contains($change.address)) { throw "$Context 出现额外 managed address：$($change.address)" }
    $actions = @($change.change.actions) -join ','
    if ($actions -ne $Expected[$change.address]) { throw "$Context 的 $($change.address) actions 错误：$actions" }
  }
  foreach ($address in $Expected.Keys) {
    if (@($managed | Where-Object { $_.address -eq $address }).Count -ne 1) { throw "$Context 缺少或重复 managed address：$address" }
  }
}

function Invoke-AwsJson([string[]]$Arguments, [switch]$AllowFailure) {
  $raw = @(& aws @Arguments --output json 2>&1) -join "`n"; $code = $LASTEXITCODE
  if ($code -ne 0) { if ($AllowFailure) { return $null }; throw "AWS CLI 失败：aws $($Arguments -join ' ')`n$raw" }
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }; $raw | ConvertFrom-Json -Depth 100
}

function Empty-VersionedBucket([string]$Endpoint, [string]$Region, [string]$Bucket) {
  $listed = Invoke-AwsJson @('--endpoint-url', $Endpoint, '--region', $Region, 's3api', 'list-object-versions', '--bucket', $Bucket) -AllowFailure
  if ($null -eq $listed) { return }
  $versionedItems = [Collections.Generic.List[object]]::new()
  foreach ($propertyName in @('Versions', 'DeleteMarkers')) {
    if ($null -ne $listed.PSObject.Properties[$propertyName]) {
      foreach ($entry in @($listed.$propertyName)) { if ($null -ne $entry) { $versionedItems.Add($entry) } }
    }
  }
  foreach ($item in $versionedItems) {
    if ($null -ne $item -and $item.Key -and $item.VersionId) { [void](Invoke-AwsJson @('--endpoint-url', $Endpoint, '--region', $Region, 's3api', 'delete-object', '--bucket', $Bucket, '--key', $item.Key, '--version-id', $item.VersionId) -AllowFailure) }
  }
  $contents = if ($null -ne $listed.PSObject.Properties['Contents']) { @($listed.Contents) } else { @() }
  foreach ($item in $contents) { if ($null -ne $item -and $item.Key) { [void](Invoke-AwsJson @('--endpoint-url', $Endpoint, '--region', $Region, 's3api', 'delete-object', '--bucket', $Bucket, '--key', $item.Key) -AllowFailure) } }
}

# 必须先校验原始 endpoint，再读 Candidate 或调用网络。
Assert-LoopbackEndpoint $LocalstackEndpoint

$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path; $producerRoot = Join-Path $candidateRoot 'producer'; $consumerRoot = Join-Path $candidateRoot 'consumer'
foreach ($root in @($producerRoot, $consumerRoot)) { if (-not (Test-Path $root -PathType Container)) { throw "缺少 root：$root" } }
$allowedTfParents = @((Get-Item -LiteralPath $producerRoot).FullName, (Get-Item -LiteralPath $consumerRoot).FullName)
$candidateConfigFiles = @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -Force -File | Where-Object { $_.Name -match '(?i)\.tf(?:\.json)?$' })
$jsonHclFiles = @($candidateConfigFiles | Where-Object { $_.Name -match '(?i)\.tf\.json$' })
if ($jsonHclFiles.Count -gt 0) { throw "禁止 JSON HCL 绕过顶层 block 审计：$($jsonHclFiles.FullName -join ', ')" }
$candidateTfFiles = @($candidateConfigFiles | Where-Object { $_.Name -match '(?i)\.tf$' })
foreach ($file in $candidateTfFiles) {
  if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "禁止 reparse Terraform 源码：$($file.FullName)" }
  if ($file.Directory.FullName -notin $allowedTfParents) { throw "禁止 candidate root 外或嵌套目录中的 Terraform 源码：$($file.FullName)" }
}
$producerRaw = (($candidateTfFiles | Where-Object { $_.Directory.FullName -eq (Get-Item -LiteralPath $producerRoot).FullName }) | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$consumerRaw = (($candidateTfFiles | Where-Object { $_.Directory.FullName -eq (Get-Item -LiteralPath $consumerRoot).FullName }) | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$producerText = Remove-HclComments $producerRaw
$consumerText = Remove-HclComments $consumerRaw
if (Test-HclHeredocOpener $producerText) { throw 'producer 禁止 HCL heredoc 绕过顶层 block 审计。' }
if (Test-HclHeredocOpener $consumerText) { throw 'consumer 禁止 HCL heredoc 绕过顶层 block 审计。' }
$allText = "$producerText`n$consumerText"
Write-Host 'Challenge 39: auditing exact top-level structure...'
if (@(Get-HclBlocks $producerText '(?m)^\s*terraform\s*\{').Count -ne 1 -or @(Get-HclBlocks $consumerText '(?m)^\s*terraform\s*\{').Count -ne 1) { throw 'producer 与 consumer 必须各自精确包含一个 terraform block。' }
Assert-ExactNamedBlocks $producerText '(?m)^\s*provider\s+"([^"]+)"\s*\{' @('aws') 'producer providers'
Assert-ExactNamedBlocks $consumerText '(?m)^\s*provider\s+"([^"]+)"\s*\{' @('aws') 'consumer providers'
Assert-ExactNamedBlocks $producerText '(?m)^\s*variable\s+"([^"]+)"\s*\{' @('aws_region', 'localstack_endpoint', 'run_id', 'contract_version', 'state_bucket', 'producer_state_key') 'producer variables'
Assert-ExactNamedBlocks $consumerText '(?m)^\s*variable\s+"([^"]+)"\s*\{' @('aws_region', 'localstack_endpoint', 'state_bucket', 'producer_state_key', 'expected_contract_version', 'release_id') 'consumer variables'
Assert-ExactAddressedBlocks $producerText '(?m)^\s*resource\s+"([^"]+)"\s+"([^"]+)"\s*\{' @('aws_s3_bucket.artifacts', 'aws_s3_bucket_versioning.artifacts') 'producer resources'
Assert-ExactAddressedBlocks $consumerText '(?m)^\s*resource\s+"([^"]+)"\s+"([^"]+)"\s*\{' @('terraform_data.contract_guard', 'aws_s3_object.release') 'consumer resources'
Assert-ExactAddressedBlocks $producerText '(?m)^\s*data\s+"([^"]+)"\s+"([^"]+)"\s*\{' @() 'producer data sources'
Assert-ExactAddressedBlocks $consumerText '(?m)^\s*data\s+"([^"]+)"\s+"([^"]+)"\s*\{' @('terraform_remote_state.producer') 'consumer data sources'
Assert-ExactNamedBlocks $producerText '(?m)^\s*output\s+"([^"]+)"\s*\{' @('delivery_contract') 'producer outputs'
Assert-ExactNamedBlocks $consumerText '(?m)^\s*output\s+"([^"]+)"\s*\{' @('consumed_contract', 'release_contract') 'consumer outputs'
if (@(Get-HclBlocks $producerText '(?m)^\s*locals\s*\{').Count -ne 0 -or @(Get-HclBlocks $consumerText '(?m)^\s*locals\s*\{').Count -ne 1) { throw 'producer 禁止 locals；consumer 必须精确包含一个 locals block。' }
foreach ($kind in @('module', 'check', 'moved', 'import', 'removed')) {
  if ($allText -match "(?m)^\s*$kind(?:\s+`"[^`"]+`")?\s*\{") { throw "禁止额外顶层 $kind block。" }
}
Write-Host 'Challenge 39: auditing provider and version contracts...'
foreach ($entry in @(@{ Text = $producerText; Name = 'producer' }, @{ Text = $consumerText; Name = 'consumer' })) {
  $v = One $entry.Text '(?m)^\s*variable\s+"localstack_endpoint"\s*\{' "$($entry.Name) localstack_endpoint"; Assignment $v 'default' '"http://localhost:4566"' "$($entry.Name) localstack_endpoint"
  $endpointValidation = One $v '(?m)^\s*validation\s*\{' "$($entry.Name) endpoint validation"
  $endpointExpression = 'can(regex("^https?://(localhost|127[.]0[.]0[.]1|\\[::1\\]):([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])\\z", var.localstack_endpoint))'
  Assignment $endpointValidation 'condition' ([regex]::Escape($endpointExpression)) "$($entry.Name) endpoint validation"
  Assert-Provider $entry.Text $entry.Name
  if ([regex]::Matches($entry.Text, 'required_version\s*=\s*"~>\s*1\.6"').Count -ne 1 -or [regex]::Matches($entry.Text, 'version\s*=\s*"~>\s*5\.100"').Count -ne 1) { throw "$($entry.Name) 版本约束错误。" }
}
if ($allText -match '(?i)(profile\s*=|(?m)^\s*token\s*=|shared_(config|credentials)|assume_role(_with_web_identity)?\s*\{|web_identity_token|credential_process|AKIA[0-9A-Z]{16})') { throw '检测到替代凭证或真实 access key。' }
Write-Host 'Challenge 39: auditing producer backend contract...'
$backend = One $producerText '(?m)^\s*backend\s+"s3"\s*\{' 'producer partial S3 backend'
if ($backend -notmatch '(?s)^\s*backend\s+"s3"\s*\{\s*\}\s*$') { throw 'producer backend 必须为空，所有参数只能由 CLI 注入。' }
$bucket = One $producerText '(?m)^\s*resource\s+"aws_s3_bucket"\s+"artifacts"\s*\{' 'artifact bucket'; Assignment $bucket 'force_destroy' 'true' 'artifact bucket'
$versioning = One $producerText '(?m)^\s*resource\s+"aws_s3_bucket_versioning"\s+"artifacts"\s*\{' 'artifact versioning'; if ($versioning -notmatch 'status\s*=\s*"Enabled"') { throw 'artifact bucket 必须启用 versioning。' }
$delivery = One $producerText '(?m)^\s*output\s+"delivery_contract"\s*\{' 'delivery_contract'; foreach ($field in @('contract_version', 'state_bucket', 'producer_state_key', 'bucket_name', 'run_id')) { if ($delivery -notmatch [regex]::Escape($field)) { throw "delivery_contract 缺少 $field。" } }
$remote = One $consumerText '(?m)^\s*data\s+"terraform_remote_state"\s+"producer"\s*\{' 'consumer remote state'; Assignment $remote 'backend' '"s3"' 'remote state'
Write-Host 'Challenge 39: auditing consumer remote-state contract...'
foreach ($pair in @(
  @('bucket', 'var\.state_bucket'), @('key', 'var\.producer_state_key'), @('region', 'var\.aws_region'), @('endpoint', 'var\.localstack_endpoint'), @('sts_endpoint', 'var\.localstack_endpoint'),
  @('access_key', '"test"'), @('secret_key', '"test"'), @('force_path_style', 'true'), @('skip_credentials_validation', 'true'), @('skip_metadata_api_check', 'true'), @('skip_requesting_account_id', 'true')
)) { Assignment $remote $pair[0] $pair[1] 'remote state config' }
$guard = One $consumerText '(?m)^\s*resource\s+"terraform_data"\s+"contract_guard"\s*\{' 'consumer contract guard'
$preconditions = @(Get-HclBlocks $guard '(?m)^\s*precondition\s*\{')
if ($preconditions.Count -ne 7) { throw 'consumer contract guard 必须精确包含七个 preconditions。' }
$semanticPatterns = [ordered]@{
  contract_version = @(
    'try\s*\(\s*local\.contract\.contract_version\s*,\s*0\s*\)\s*==\s*var\.expected_contract_version',
    'var\.expected_contract_version\s*==\s*1'
  )
  region = @('try\s*\(\s*local\.contract\.region\s*,\s*""\s*\)\s*==\s*var\.aws_region')
  state_bucket = @('try\s*\(\s*local\.contract\.producer\.state_bucket\s*,\s*""\s*\)\s*==\s*var\.state_bucket')
  state_key = @('try\s*\(\s*local\.contract\.producer\.state_key\s*,\s*""\s*\)\s*==\s*var\.producer_state_key')
  artifact_bucket = @(
    'can\s*\(\s*regex\s*\(',
    ([regex]::Escape('"^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$"')),
    'try\s*\(\s*local\.contract\.artifacts\.bucket_name\s*,\s*""\s*\)'
  )
  versioning = @('try\s*\(\s*local\.contract\.artifacts\.versioning\s*,\s*""\s*\)\s*==\s*"Enabled"')
  run_id = @(
    'can\s*\(\s*regex\s*\(',
    ([regex]::Escape('"^[a-z0-9-]{3,32}$"')),
    'try\s*\(\s*local\.contract\.run_id\s*,\s*""\s*\)'
  )
}
$semanticTokens = [ordered]@{
  contract_version = 'local\.contract\.contract_version|var\.expected_contract_version'
  region           = 'local\.contract\.region|var\.aws_region'
  state_bucket     = 'local\.contract\.producer\.state_bucket|var\.state_bucket'
  state_key        = 'local\.contract\.producer\.state_key|var\.producer_state_key'
  artifact_bucket  = 'local\.contract\.artifacts\.bucket_name'
  versioning       = 'local\.contract\.artifacts\.versioning'
  run_id           = 'local\.contract\.run_id'
}
$matchedSemantics = [Collections.Generic.List[string]]::new()
foreach ($block in $preconditions) {
  $expression = Get-ConditionExpression $block 'consumer contract precondition'
  if ($expression -match '\|\|' -or $expression -match '(?i)(?<![\w"])true(?![\w"])') { throw 'precondition 禁止使用 OR/true 构造 catch-all 或平凡 guard。' }
  $referencedSemantics = @($semanticTokens.Keys | Where-Object { $expression -match $semanticTokens[$_] })
  if ($referencedSemantics.Count -ne 1) { throw '每个 precondition 必须只引用 contract_version/region/state_bucket/state_key/artifact_bucket/versioning/run_id 中的一类。' }
  $semanticMatches = @($semanticPatterns.Keys | Where-Object {
      $required = $semanticPatterns[$_]
      @($required | Where-Object { $expression -notmatch $_ }).Count -eq 0
    })
  if ($semanticMatches.Count -ne 1 -or $semanticMatches[0] -ne $referencedSemantics[0]) { throw '每个 precondition 必须实现且只实现一个完整合同语义，禁止 catch-all 或平凡 guard。' }
  $matchedSemantics.Add($semanticMatches[0])
}
if (($matchedSemantics | Sort-Object) -join ',' -ne 'artifact_bucket,contract_version,region,run_id,state_bucket,state_key,versioning') { throw '七类合同 precondition 必须各自精确出现一次。' }
$object = One $consumerText '(?m)^\s*resource\s+"aws_s3_object"\s+"release"\s*\{' 'release object'
if ($object -notmatch 'releases/\$\{var\.release_id\}\.json' -or $object -notmatch 'depends_on\s*=\s*\[terraform_data\.contract_guard\]') { throw 'release object 路径或合同依赖错误。' }

$health = Invoke-RestMethod -Uri "$LocalstackEndpoint/_localstack/health" -TimeoutSec 5
foreach ($svc in @('s3', 'dynamodb', 'sts')) { if ($health.services.$svc -notin @('available', 'running')) { throw "LocalStack $svc 不可用。" } }
Write-Host 'Challenge 39: static contracts passed; entering isolated workflow...'

$tempBase = [IO.Path]::GetTempPath(); $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 10); $runId = "c39$suffix"
$temp = Join-Path $tempBase "tfpro-c39-$suffix"; $work = Join-Path $temp 'candidate'; $producer = Join-Path $work 'producer'; $consumer = Join-Path $work 'consumer'
$stateBucket = "tfpro-c39-$suffix-state"; $lockTable = "tfpro-c39-$suffix-locks"; $stateKey = 'producer/terraform.tfstate'; $artifactBucket = "$runId-artifacts"
$oldAccess = $env:AWS_ACCESS_KEY_ID; $oldSecret = $env:AWS_SECRET_ACCESS_KEY; $oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'
$createdBucket = $false; $createdTable = $false; $producerApplied = $false; $copied = $false; $failure = $null
$cleanupFailures = [Collections.Generic.List[string]]::new()
$producerVars = @("-var=localstack_endpoint=$LocalstackEndpoint", "-var=run_id=$runId", "-var=state_bucket=$stateBucket", "-var=producer_state_key=$stateKey")
$consumerVars = @("-var=localstack_endpoint=$LocalstackEndpoint", "-var=state_bucket=$stateBucket", "-var=producer_state_key=$stateKey", '-var=release_id=release-v1')
$backendArgs = @(
  "-backend-config=bucket=$stateBucket", "-backend-config=key=$stateKey", '-backend-config=region=us-east-1', "-backend-config=endpoint=$LocalstackEndpoint", "-backend-config=dynamodb_endpoint=$LocalstackEndpoint", "-backend-config=sts_endpoint=$LocalstackEndpoint",
  '-backend-config=access_key=test', '-backend-config=secret_key=test', '-backend-config=force_path_style=true', '-backend-config=skip_credentials_validation=true', '-backend-config=skip_metadata_api_check=true', '-backend-config=skip_requesting_account_id=true', "-backend-config=dynamodb_table=$lockTable"
)
try {
  New-Item -ItemType Directory -Force -Path $temp | Out-Null; Copy-Clean $candidateRoot $work; $copied = $true
  Copy-Clean (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $temp 'fixtures')
  foreach ($case in @(@{ Root = $producer; File = 'producer.tftest.hcl'; Count = 4 }, @{ Root = $consumer; File = 'consumer.tftest.hcl'; Count = 10 })) {
    New-Item -ItemType Directory -Force -Path (Join-Path $case.Root 'tests-generated') | Out-Null; Copy-Item -LiteralPath (Join-Path $PSScriptRoot $case.File) -Destination (Join-Path $case.Root "tests-generated\$($case.File)")
    Tf $case.Root @('fmt', '-check', '-recursive') | Out-Null; Tf $case.Root @('init', '-backend=false', '-input=false', '-no-color') | Out-Null; Tf $case.Root @('validate', '-no-color') | Out-Null; ExactTests $case.Root $case.Count
  }
  if ($SkipE2E) { Write-Host 'PASS: Challenge 39 static + 4 producer tests + 10 consumer tests.'; return }

  [void](Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'create-bucket', '--bucket', $stateBucket)); $createdBucket = $true
  [void](Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'dynamodb', 'create-table', '--table-name', $lockTable, '--attribute-definitions', 'AttributeName=LockID,AttributeType=S', '--key-schema', 'AttributeName=LockID,KeyType=HASH', '--billing-mode', 'PAY_PER_REQUEST')); $createdTable = $true

  # producer 尚未发布 state 时，consumer 必须失败。
  $before = @(& terraform "-chdir=$consumer" plan -input=false -no-color @consumerVars 2>&1); $beforeCode = $LASTEXITCODE; $before | Out-Host
  if ($beforeCode -eq 0 -or ($before -join "`n") -notmatch '(?i)(unable to find remote state|NoSuchKey|does not have any outputs)') { throw 'consumer-before-producer 必须因远端 state 不存在而失败。' }

  Tf $producer (@('init', '-reconfigure', '-input=false', '-no-color') + $backendArgs) | Out-Null
  $backendMeta = Get-Content -Raw (Join-Path $producer '.terraform\terraform.tfstate') | ConvertFrom-Json -Depth 50
  $cfg = $backendMeta.backend.config
  if ($cfg.bucket -ne $stateBucket -or $cfg.key -ne $stateKey -or $cfg.dynamodb_table -ne $lockTable -or $cfg.endpoint -ne $LocalstackEndpoint) { throw 'TF1.6 backend metadata 未保留隔离 bucket/key/table/endpoint。' }
  $producerPlan = Join-Path $producer 'producer.tfplan'; Tf $producer (@('plan', '-input=false', '-no-color', "-out=$producerPlan") + $producerVars) | Out-Null
  Assert-ExactManagedPlan $producer $producerPlan ([ordered]@{
      'aws_s3_bucket.artifacts'            = 'create'
      'aws_s3_bucket_versioning.artifacts' = 'create'
    }) 'producer initial saved plan'
  $producerApplied = $true
  Tf $producer @('apply', '-input=false', '-no-color', $producerPlan) | Out-Null
  $headState = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'head-object', '--bucket', $stateBucket, '--key', $stateKey)
  if ($null -eq $headState -or $headState.ContentLength -lt 100) { throw 'producer state 未真实写入 LocalStack S3。' }

  $consumerPlan = Join-Path $consumer 'consumer.tfplan'; Tf $consumer (@('plan', '-input=false', '-no-color', "-out=$consumerPlan") + $consumerVars) | Out-Null
  Assert-ExactManagedPlan $consumer $consumerPlan ([ordered]@{
      'aws_s3_object.release'         = 'create'
      'terraform_data.contract_guard' = 'create'
    }) 'consumer initial saved plan'
  Tf $consumer @('apply', '-input=false', '-no-color', $consumerPlan) | Out-Null
  $contractRaw = @(& terraform "-chdir=$consumer" output -json consumed_contract 2>&1) -join "`n"; if ($LASTEXITCODE) { throw '无法读取 consumed_contract。' }; $contract = $contractRaw | ConvertFrom-Json -Depth 30
  if ($contract.contract_version -ne 1 -or $contract.region -ne 'us-east-1' -or $contract.producer.state_bucket -ne $stateBucket -or $contract.producer.state_key -ne $stateKey -or $contract.artifacts.bucket_name -ne $artifactBucket -or $contract.artifacts.versioning -ne 'Enabled' -or $contract.run_id -ne $runId) { throw '真实 remote-state contract 内容错误。' }
  $realVersioning = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'get-bucket-versioning', '--bucket', $artifactBucket)
  if ($realVersioning.Status -ne 'Enabled') { throw '真实 artifact bucket versioning 未启用。' }
  $tags = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'get-object-tagging', '--bucket', $artifactBucket, '--key', 'releases/release-v1.json')
  $tagMap = @{}; foreach ($tag in @($tags.TagSet)) { $tagMap[$tag.Key] = $tag.Value }
  if ($tagMap.ReleaseId -ne 'release-v1' -or $tagMap.RunId -ne $runId -or $tagMap.Lab -ne 'challenge-39') { throw '真实 release object 标签错误。' }
  $releaseBodyPath = Join-Path $temp 'release-v1.json'
  [void](Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'get-object', '--bucket', $artifactBucket, '--key', 'releases/release-v1.json', $releaseBodyPath))
  try { $releaseBody = Get-Content -Raw -LiteralPath $releaseBodyPath | ConvertFrom-Json -Depth 20 } catch { throw "真实 release object 正文不是合法 JSON：$_" }
  $releaseFields = @($releaseBody.PSObject.Properties.Name | Sort-Object)
  if (($releaseFields -join ',') -ne 'contract_version,managed_by,producer_run_id,release_id') { throw "真实 release object 正文必须精确包含四个字段，实际为：$($releaseFields -join ',')" }
  if ($releaseBody.contract_version -ne $contract.contract_version -or $releaseBody.release_id -ne 'release-v1' -or
    $releaseBody.producer_run_id -ne $contract.run_id -or $releaseBody.managed_by -ne 'terraform') { throw '真实 release object 正文与 remote-state contract 不一致。' }

  # 真实 remote object drift 必须形成可恢复的 saved plan。
  $driftFile = Join-Path $temp 'drift.json'; Set-Content -LiteralPath $driftFile -Value '{"drift":true}' -NoNewline
  [void](Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'put-object', '--bucket', $artifactBucket, '--key', 'releases/release-v1.json', '--body', $driftFile, '--content-type', 'application/json'))
  $driftPlan = Join-Path $consumer 'drift.tfplan'; Tf $consumer (@('plan', '-input=false', '-no-color', "-out=$driftPlan") + $consumerVars) | Out-Null
  $driftJson = @(& terraform "-chdir=$consumer" show -json $driftPlan 2>&1) -join "`n" | ConvertFrom-Json -Depth 100
  $changes = @($driftJson.resource_changes | Where-Object { $_.mode -eq 'managed' -and $_.change.actions -notcontains 'no-op' })
  if ($changes.Count -ne 1 -or $changes[0].address -ne 'aws_s3_object.release' -or (@($changes[0].change.actions) -join ',') -ne 'update') { throw 'drift recovery 必须只有 aws_s3_object.release 的原位更新。' }
  Tf $consumer @('apply', '-input=false', '-no-color', $driftPlan) | Out-Null

  # 同一 consumer state lineage 前进后，旧 saved plan 必须被 Terraform 拒绝。
  $stalePlan = Join-Path $consumer 'stale.tfplan'; Tf $consumer (@('plan', '-input=false', '-no-color', "-out=$stalePlan") + ($consumerVars | Where-Object { $_ -notlike '-var=release_id=*' }) + @('-var=release_id=stale-release')) | Out-Null
  Tf $consumer (@('apply', '-auto-approve', '-input=false', '-no-color') + ($consumerVars | Where-Object { $_ -notlike '-var=release_id=*' }) + @('-var=release_id=lineage-bump')) | Out-Null
  $staleOut = @(& terraform "-chdir=$consumer" apply -input=false -no-color $stalePlan 2>&1); $staleCode = $LASTEXITCODE; $staleOut | Out-Host
  if ($staleCode -eq 0 -or ($staleOut -join "`n") -notmatch '(?i)saved plan is stale') { throw 'state serial 前进后旧 saved plan 必须以 stale 拒绝。' }
  $restore = Join-Path $consumer 'restore.tfplan'; Tf $consumer (@('plan', '-input=false', '-no-color', "-out=$restore") + $consumerVars) | Out-Null; Tf $consumer @('apply', '-input=false', '-no-color', $restore) | Out-Null
  $clean = Tf $consumer (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $consumerVars) @(0, 2); if ($clean.Code -ne 0) { throw 'consumer 恢复后不是 clean plan。' }

  # 逆依赖顺序销毁：consumer -> producer。
  Tf $consumer (@('destroy', '-auto-approve', '-input=false', '-no-color') + $consumerVars) | Out-Null
  Tf $producer (@('destroy', '-auto-approve', '-input=false', '-no-color') + $producerVars) | Out-Null
} catch { $failure = $_ } finally {
  if ($copied) {
    if (Test-Path (Join-Path $consumer 'terraform.tfstate')) {
      try {
        $destroyOutput = @(& terraform "-chdir=$consumer" destroy -auto-approve -input=false -no-color @consumerVars 2>&1)
        if ($LASTEXITCODE -ne 0) { $cleanupFailures.Add("consumer fallback destroy exit=$LASTEXITCODE：$($destroyOutput -join ' ')") }
      } catch { $cleanupFailures.Add("consumer fallback destroy 异常：$_") }
    }
    if (Test-Path (Join-Path $producer '.terraform\terraform.tfstate')) {
      try {
        $destroyOutput = @(& terraform "-chdir=$producer" destroy -auto-approve -input=false -no-color @producerVars 2>&1)
        if ($LASTEXITCODE -ne 0) { $cleanupFailures.Add("producer fallback destroy exit=$LASTEXITCODE：$($destroyOutput -join ' ')") }
      } catch { $cleanupFailures.Add("producer fallback destroy 异常：$_") }
    }
  }
  if ($producerApplied) {
    try { Empty-VersionedBucket $LocalstackEndpoint 'us-east-1' $artifactBucket } catch { $cleanupFailures.Add("artifact bucket 清空失败：$_") }
    try { [void](Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'delete-bucket', '--bucket', $artifactBucket) -AllowFailure) } catch { $cleanupFailures.Add("artifact bucket 删除失败：$_") }
  }
  if ($createdBucket) {
    try { Empty-VersionedBucket $LocalstackEndpoint 'us-east-1' $stateBucket } catch { $cleanupFailures.Add("backend bucket 清空失败：$_") }
    try { [void](Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'delete-bucket', '--bucket', $stateBucket) -AllowFailure) } catch { $cleanupFailures.Add("backend bucket 删除失败：$_") }
  }
  if ($createdTable) {
    try { [void](Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'dynamodb', 'delete-table', '--table-name', $lockTable) -AllowFailure) } catch { $cleanupFailures.Add("DynamoDB lock table 删除失败：$_") }
  }
  try {
    $buckets = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'list-buckets')
    $remainingBuckets = @($buckets.Buckets | Where-Object { $_.Name -in @($stateBucket, $artifactBucket) })
    if ($remainingBuckets.Count -gt 0) { $cleanupFailures.Add("LocalStack S3 残留：$($remainingBuckets.Name -join ',')") }
  } catch { $cleanupFailures.Add("S3 残留审计失败：$_") }
  try {
    $tables = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'dynamodb', 'list-tables')
    if (@($tables.TableNames) -contains $lockTable) { $cleanupFailures.Add("LocalStack DynamoDB 残留：$lockTable") }
  } catch { $cleanupFailures.Add("DynamoDB 残留审计失败：$_") }
  try {
    $resolved = [IO.Path]::GetFullPath($temp)
    if (-not ($resolved.StartsWith([IO.Path]::GetFullPath($tempBase), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^tfpro-c39-[0-9a-f]{10}$')) { throw "拒绝不安全临时目录：$resolved" }
    if (Test-Path $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop }
    if (Test-Path $resolved) { throw "临时目录删除后仍存在：$resolved" }
  } catch { $cleanupFailures.Add("临时目录清理失败：$_") }
  try {
    $env:AWS_ACCESS_KEY_ID = $oldAccess
    $env:AWS_SECRET_ACCESS_KEY = $oldSecret
    $env:AWS_DEFAULT_REGION = $oldRegion
  } catch {
    $cleanupFailures.Add("AWS 环境变量恢复失败：$_")
  }
}
if ($cleanupFailures.Count -gt 0) {
  $cleanupMessage = $cleanupFailures -join "`n - "
  if ($failure) { throw "Challenge 39 主流程失败：$failure`nCleanup failures:`n - $cleanupMessage" }
  throw "Challenge 39 cleanup failed:`n - $cleanupMessage"
}
if ($failure) { throw $failure }
Write-Host 'PASS: Challenge 39 exact tests + real TF1.6 S3 backend/DynamoDB lock + remote contract + stale plan/drift + reverse destroy + zero residue.'
