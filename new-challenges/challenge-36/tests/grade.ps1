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
  if (-not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri)) { throw "LocalstackEndpoint 必须是绝对 URI。" }
  $hostName = $uri.Host.Trim('[', ']').ToLowerInvariant()
  if ($uri.Scheme -notin @('http', 'https') -or $hostName -notin @('localhost', '127.0.0.1', '::1') -or
    -not [string]::IsNullOrEmpty($uri.UserInfo) -or $uri.AbsolutePath -ne '/' -or
    -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw "LocalstackEndpoint 仅允许 loopback HTTP(S) 根地址。"
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
      if ($current -eq "`n") { [void]$builder.Append($current); $state = 'code' } else { [void]$builder.Append(' ') }
    }
    else {
      if ($current -eq '*' -and $next -eq '/') { [void]$builder.Append('  '); $i++; $state = 'code' }
      elseif ($current -eq "`n") { [void]$builder.Append($current) } else { [void]$builder.Append(' ') }
    }
  }
  return $builder.ToString()
}

function Move-PastHclTrivia([string]$Text, [int]$Start, [string]$Context) {
  $i = $Start
  while ($i -lt $Text.Length) {
    while ($i -lt $Text.Length -and ([char]::IsWhiteSpace($Text[$i]) -or $Text[$i] -eq [char]0xfeff)) { $i++ }
    if ($i -ge $Text.Length) { break }
    if ($Text[$i] -eq '#') {
      while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
      continue
    }
    if ($i + 1 -lt $Text.Length -and $Text[$i] -eq '/' -and $Text[$i + 1] -eq '/') {
      $i += 2
      while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
      continue
    }
    if ($i + 1 -lt $Text.Length -and $Text[$i] -eq '/' -and $Text[$i + 1] -eq '*') {
      $end = $Text.IndexOf('*/', $i + 2, [StringComparison]::Ordinal)
      if ($end -lt 0) { throw "$Context 包含未闭合 block comment。" }
      $i = $end + 2
      continue
    }
    break
  }
  return $i
}

function Read-HclQuotedToken([string]$Text, [int]$Start, [string]$Context) {
  $builder = [Text.StringBuilder]::new()
  for ($i = $Start + 1; $i -lt $Text.Length; $i++) {
    $c = $Text[$i]
    if ($c -eq '\') {
      if ($i + 1 -ge $Text.Length) { throw "$Context 包含未闭合 quoted token。" }
      [void]$builder.Append($c); $i++; [void]$builder.Append($Text[$i]); continue
    }
    if ($c -eq '"') { return [pscustomobject]@{ Value = $builder.ToString(); Next = $i + 1 } }
    [void]$builder.Append($c)
  }
  throw "$Context 包含未闭合 quoted token。"
}

function Get-TopLevelHclBlockSignatures([string]$Text, [string]$Context) {
  $blocks = [Collections.Generic.List[string]]::new()
  $i = 0
  while ($i -lt $Text.Length) {
    $i = Move-PastHclTrivia $Text $i $Context
    if ($i -ge $Text.Length) { break }
    if (-not ([char]::IsLetter($Text[$i]) -or $Text[$i] -eq '_')) { throw "$Context 顶层含不可审计语法，offset=$i。" }
    $start = $i; $i++
    while ($i -lt $Text.Length -and ([char]::IsLetterOrDigit($Text[$i]) -or $Text[$i] -in @('_', '-'))) { $i++ }
    $parts = [Collections.Generic.List[string]]::new()
    $parts.Add($Text.Substring($start, $i - $start))
    $i = Move-PastHclTrivia $Text $i $Context
    while ($i -lt $Text.Length -and $Text[$i] -eq '"') {
      $token = Read-HclQuotedToken $Text $i $Context
      $parts.Add($token.Value); $i = Move-PastHclTrivia $Text $token.Next $Context
    }
    if ($i -ge $Text.Length -or $Text[$i] -ne '{') { throw "$Context 顶层 block header 不可审计：$($parts -join ':')。" }
    $blocks.Add(($parts -join ':')); $depth = 1; $i++
    while ($i -lt $Text.Length -and $depth -gt 0) {
      $next = Move-PastHclTrivia $Text $i $Context
      if ($next -ne $i) { $i = $next; continue }
      if ($Text[$i] -eq '"') { $token = Read-HclQuotedToken $Text $i $Context; $i = $token.Next; continue }
      if ($i + 1 -lt $Text.Length -and $Text[$i] -eq '<' -and $Text[$i + 1] -eq '<') {
        $heredoc = [regex]::Match($Text.Substring($i), '\A<<-?([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?:\r?\n)')
        if ($heredoc.Success) {
          $bodyStart = $i + $heredoc.Length; $marker = $heredoc.Groups[1].Value
          $terminator = [regex]::Match($Text.Substring($bodyStart), '(?m)^[ \t]*' + [regex]::Escape($marker) + '[ \t]*\r?$')
          if (-not $terminator.Success) { throw "$Context 包含未闭合 heredoc $marker。" }
          $lineEnd = $Text.IndexOf("`n", $bodyStart + $terminator.Index + $terminator.Length)
          $i = if ($lineEnd -lt 0) { $Text.Length } else { $lineEnd + 1 }
          continue
        }
      }
      if ($Text[$i] -eq '{') { $depth++ }
      elseif ($Text[$i] -eq '}') { $depth-- }
      $i++
    }
    if ($depth -ne 0) { throw "$Context 包含未闭合顶层 block：$($parts -join ':')。" }
  }
  return @($blocks)
}

function Get-AllowedTfFiles([string]$Root, [string[]]$AllowedRelativeDirectories, [string]$Context) {
  $trim = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd($trim)
  $allowed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($relative in $AllowedRelativeDirectories) {
    $directory = if ($relative -eq '.') { $rootFull } else { [IO.Path]::GetFullPath((Join-Path $rootFull $relative)).TrimEnd($trim) }
    if ($directory -ne $rootFull -and -not $directory.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "$Context 内部 allowed path 越界。" }
    [void]$allowed.Add($directory)
  }
  $files = @(Get-ChildItem -LiteralPath $rootFull -Recurse -Force -File | Where-Object { $_.Name -match '(?i)\.tf(?:\.json)?$' })
  foreach ($file in $files) {
    if ($file.Name -match '(?i)\.tf\.json$') { throw "$Context 禁止 JSON HCL：$($file.FullName)" }
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Context 禁止 reparse .tf：$($file.FullName)" }
    $directory = [IO.Path]::GetFullPath($file.DirectoryName).TrimEnd($trim)
    if (-not $allowed.Contains($directory)) { throw "$Context 检测到非白名单 HCL 目录：$($file.FullName)" }
    $cursor = Get-Item -LiteralPath $directory -Force; $reachedRoot = $false
    while ($null -ne $cursor) {
      if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Context 禁止 reparse HCL 目录：$($cursor.FullName)" }
      if ([string]::Equals([IO.Path]::GetFullPath($cursor.FullName).TrimEnd($trim), $rootFull, [StringComparison]::OrdinalIgnoreCase)) { $reachedRoot = $true; break }
      $cursor = $cursor.Parent
    }
    if (-not $reachedRoot) { throw "$Context HCL 路径不在 Candidate 内：$($file.FullName)" }
  }
  return @($files | Sort-Object FullName)
}

function Assert-ExactTopLevelBlocks([object[]]$Files, [string[]]$Expected, [string]$Context) {
  $actual = [Collections.Generic.List[string]]::new()
  foreach ($file in $Files) {
    foreach ($signature in @(Get-TopLevelHclBlockSignatures (Get-Content -LiteralPath $file.FullName -Raw) $file.FullName)) { $actual.Add($signature) }
  }
  $wanted = [Collections.Generic.List[string]]::new(); foreach ($signature in $Expected) { $wanted.Add($signature) }
  $actual.Sort([StringComparer]::Ordinal); $wanted.Sort([StringComparer]::Ordinal)
  $same = $actual.Count -eq $wanted.Count
  if ($same) {
    for ($i = 0; $i -lt $actual.Count; $i++) {
      if (-not [string]::Equals($actual[$i], $wanted[$i], [StringComparison]::Ordinal)) { $same = $false; break }
    }
  }
  if (-not $same) { throw "$Context 顶层 block 白名单不匹配。`nExpected: $($wanted -join ', ')`nActual: $($actual -join ', ')" }
}

function Get-HclBlocks([string]$Text, [string]$HeaderPattern) {
  $blocks = [Collections.Generic.List[string]]::new()
  foreach ($match in [regex]::Matches($Text, $HeaderPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    $open = $Text.IndexOf('{', $match.Index)
    if ($open -lt 0) { continue }
    $depth = 0; $inString = $false
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
        if ($depth -eq 0) { $blocks.Add($Text.Substring($match.Index, $i - $match.Index + 1)); break }
      }
    }
  }
  return @($blocks)
}

function Test-ExactAssignment([string]$Block, [string]$Name, [string]$ValuePattern) {
  $escaped = [regex]::Escape($Name)
  return [regex]::Matches($Block, "(?m)^\s*$escaped\s*=").Count -eq 1 -and
    [regex]::Matches($Block, "(?m)^\s*$escaped\s*=\s*$ValuePattern\s*$").Count -eq 1
}

function Assert-AwsProviderContract([string]$Source) {
  $safe = Remove-HclComments $Source
  if ([regex]::Matches($safe, '(?m)^\s*required_version\s*=\s*"~>\s*1\.6"\s*$').Count -ne 1 -or
    [regex]::Matches($safe, '(?m)^\s*version\s*=\s*"~>\s*5\.100\.0"\s*$').Count -ne 1) {
    throw '必须精确约束 Terraform ~> 1.6 与 hashicorp/aws ~> 5.100.0。'
  }
  $variables = @(Get-HclBlocks $safe '(?m)^\s*variable\s+"localstack_endpoint"\s*\{')
  if ($variables.Count -ne 1 -or -not (Test-ExactAssignment $variables[0] 'default' '"http://localhost:4566"')) {
    throw 'localstack_endpoint variable 必须唯一且默认值精确。'
  }
  $validations = @(Get-HclBlocks $variables[0] '(?m)^\s*validation\s*\{')
  if ($validations.Count -ne 1 -or $validations[0] -notmatch '\\\\z') { throw 'localstack_endpoint 必须使用整串 \\z loopback validation。' }
  $providers = @(Get-HclBlocks $safe '(?m)^\s*provider\s+"aws"\s*\{')
  if ($providers.Count -ne 1) { throw '必须且只能有一个 aws provider block。' }
  $provider = $providers[0]
  $required = [ordered]@{
    region = 'var\.aws_region'; access_key = '"test"'; secret_key = '"test"'
    skip_credentials_validation = 'true'; skip_metadata_api_check = 'true'; skip_requesting_account_id = 'true'; s3_use_path_style = 'true'
  }
  foreach ($entry in $required.GetEnumerator()) {
    if (-not (Test-ExactAssignment $provider $entry.Key $entry.Value)) { throw "provider 必须精确设置 $($entry.Key)。" }
  }
  $endpoints = @(Get-HclBlocks $provider '(?m)^\s*endpoints\s*\{')
  if ($endpoints.Count -ne 1) { throw '必须且只能有一个 endpoints block。' }
  $keys = @([regex]::Matches($endpoints[0], '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  if (($keys -join ',') -ne 's3,sts') { throw 'endpoints 必须精确包含 s3、sts。' }
  foreach ($service in @('s3', 'sts')) {
    if (-not (Test-ExactAssignment $endpoints[0] $service 'var\.localstack_endpoint')) { throw "$service endpoint 必须引用 var.localstack_endpoint。" }
  }
  if ($safe -match '(?im)^\s*(?:profile|token|shared_config_files|shared_credentials_files|web_identity_token_file)\s*=|shared_credentials|^\s*assume_role(?:_with_web_identity)?\s*\{|AKIA[0-9A-Z]{16}') {
    throw '禁止替代凭证源、AssumeRole 或疑似真实 AWS key。'
  }
}

function Assert-SourceContract([string]$Source) {
  $safe = Remove-HclComments $Source
  foreach ($name in @('manifest_not_empty', 'artifact_ids_unique', 'object_keys_unique', 'artifact_fields_valid', 'artifact_sources_confined', 'artifact_sources_exist')) {
    if (@(Get-HclBlocks $safe "(?m)^\s*check\s+`"$name`"\s*\{").Count -ne 1) { throw "缺少唯一 check.$name。" }
  }
  $required = @(
    'data\s+"aws_caller_identity"\s+"current"\s*\{',
    'resource\s+"aws_s3_bucket"\s+"release"\s*\{',
    'resource\s+"aws_s3_object"\s+"artifact"\s*\{'
  )
  foreach ($pattern in $required) { if ([regex]::Matches($safe, $pattern).Count -ne 1) { throw "结构缺失或重复：$pattern" } }
  foreach ($pattern in @(
      'jsondecode\(file\(var\.manifest_path\)\)',
      'artifact\.artifact_id\s*=>\s*artifact\.\.\.',
      'artifact\.object_key\s*=>\s*artifact\.\.\.',
      'alltrue\(\[for\s+group\s+in\s+values\(local\.artifact_groups\)\s*:\s*length\(group\)\s*==\s*1\]\)',
      'alltrue\(\[for\s+group\s+in\s+values\(local\.object_key_groups\)\s*:\s*length\(group\)\s*==\s*1\]\)',
      '!startswith\(artifact\.source,\s*"\.\./"\)',
      'fileexists\("\$\{var\.artifact_root\}/\$\{artifact\.source\}"\)',
      'for_each\s*=\s*local\.deployable_artifacts',
      'source_hash\s*=\s*filesha256\(',
      'etag\s*=\s*filemd5\(',
      'content_type\s*=\s*each\.value\.content_type',
      'releaseid\s*=\s*var\.release_id',
      'artifactid\s*=\s*each\.key',
      'RunId\s*=\s*var\.run_id'
    )) { if ($safe -notmatch $pattern) { throw "实现合同缺少实质表达式：$pattern" } }
  if ($safe -match '(?m)^\s*count\s*=|ignore_changes\s*=') { throw '禁止 count 身份或 ignore_changes 绕过漂移。' }
}

function Copy-CleanTree([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Where-Object { $_.Name -notin @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
  }
}

function Invoke-Terraform([string]$Directory, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0)) {
  & terraform "-chdir=$Directory" @Arguments | Out-Host
  $code = $LASTEXITCODE
  if ($code -notin $AllowedExitCodes) { throw "terraform $($Arguments -join ' ') 失败，exit=$code" }
  return $code
}

function Invoke-ExactTests([string]$Directory, [int]$Expected) {
  $output = @(& terraform "-chdir=$Directory" test -test-directory=tests -no-color 2>&1)
  $code = $LASTEXITCODE; $output | Out-Host; $text = $output -join "`n"
  $summary = [regex]::Matches($text, '(?m)^Success!\s+([0-9]+) passed,\s+0 failed\.\s*$')
  $runs = [regex]::Matches($text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$')
  if ($code -ne 0 -or $summary.Count -ne 1 -or [int]$summary[0].Groups[1].Value -ne $Expected -or $runs.Count -ne $Expected) {
    throw "canonical tests 必须精确通过 $Expected/$Expected。"
  }
}

function Invoke-AwsJson([string[]]$Arguments) {
  $output = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 @Arguments --output json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "aws $($Arguments -join ' ') 失败：$($output -join "`n")" }
  $text = $output -join "`n"
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  return ($text | ConvertFrom-Json -Depth 100)
}

function Assert-Tag([object[]]$Tags, [string]$Key, [string]$Value, [string]$Label) {
  $matches = @($Tags | Where-Object { $_.Key -eq $Key })
  if ($matches.Count -ne 1 -or $matches[0].Value -ne $Value) { throw "$Label 缺少唯一 $Key=$Value tag。" }
}

Assert-LoopbackEndpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tfFiles = @(Get-AllowedTfFiles $candidatePath @('.') 'Challenge 36')
Assert-ExactTopLevelBlocks $tfFiles @(
  'terraform', 'provider:aws',
  'variable:aws_region', 'variable:localstack_endpoint', 'variable:name_prefix', 'variable:release_id', 'variable:run_id', 'variable:manifest_path', 'variable:artifact_root',
  'data:aws_caller_identity:current', 'locals',
  'check:manifest_not_empty', 'check:artifact_ids_unique', 'check:object_keys_unique', 'check:artifact_fields_valid', 'check:artifact_sources_confined', 'check:artifact_sources_exist',
  'resource:aws_s3_bucket:release', 'resource:aws_s3_object:artifact',
  'output:active_artifact_ids', 'output:resource_addresses', 'output:release_contract'
) 'Challenge 36 root'
$source = ($tfFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
Assert-AwsProviderContract $source
Assert-SourceContract $source

$suffix = ([Guid]::NewGuid().ToString('N')).Substring(0, 10)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c36-$suffix"
$workDir = Join-Path $tempRoot 'candidate'
$namePrefix = "c36-$suffix"
$releaseId = "rel-$suffix"
$runId = "run-$suffix"
$commonVars = @("-var=name_prefix=$namePrefix", "-var=release_id=$releaseId", "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
$oldAccess = $env:AWS_ACCESS_KEY_ID; $oldSecret = $env:AWS_SECRET_ACCESS_KEY; $oldRegion = $env:AWS_DEFAULT_REGION; $oldRelease = $env:TF_VAR_release_id
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'
$remoteMutationStarted = $false
$bucket = "$namePrefix-$releaseId"

try {
  Copy-CleanTree $candidatePath $workDir
  Copy-Item -LiteralPath (Join-Path $labRoot 'fixtures') -Destination (Join-Path $tempRoot 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $workDir 'tests') | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $workDir 'tests\canonical.tftest.hcl') -Force
  Invoke-Terraform $workDir @('fmt', '-check', '-recursive')
  Invoke-Terraform $workDir @('init', '-backend=false', '-input=false', '-no-color')
  Invoke-Terraform $workDir @('validate', '-no-color')
  Invoke-ExactTests $workDir 12
  if ($SkipE2E) { Write-Host 'PASS: Challenge 36 精确 12/12 canonical tests（跳过 E2E）。'; return }

  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null }
  catch { throw "LocalStack 不可用：$LocalstackEndpoint" }
  $remoteMutationStarted = $true
  Remove-Item -LiteralPath (Join-Path $workDir 'tests') -Recurse -Force
  $planPath = Join-Path $workDir 'reviewed.tfplan'
  Invoke-Terraform $workDir (@('plan', "-out=$planPath", '-input=false', '-no-color') + $commonVars)
  $planJson = (& terraform "-chdir=$workDir" show -json $planPath) | ConvertFrom-Json -Depth 100
  if ($LASTEXITCODE -ne 0) { throw '无法读取 saved plan JSON。' }
  $changes = @($planJson.resource_changes | Where-Object { $_.mode -eq 'managed' })
  $expected = @('aws_s3_bucket.release', 'aws_s3_object.artifact["api-config"]', 'aws_s3_object.artifact["release-notes"]', 'aws_s3_object.artifact["worker-bootstrap"]') | Sort-Object
  $actual = @($changes | ForEach-Object { [string]$_.address } | Sort-Object)
  if (($actual -join ',') -ne ($expected -join ',')) { throw "saved plan graph 不精确：$($actual -join ', ')" }
  if (@($changes | Where-Object { (@($_.change.actions) -join ',') -ne 'create' }).Count -ne 0) { throw '首次 saved plan 必须全为 create。' }
  foreach ($change in @($changes | Where-Object { $_.type -eq 'aws_s3_object' })) {
    if ([string]::IsNullOrWhiteSpace([string]$change.change.after.key) -or [string]::IsNullOrWhiteSpace([string]$change.change.after.source_hash) -or
      $change.change.after.metadata.releaseid -ne $releaseId -or $change.change.after.metadata.runid -ne $runId -or $change.change.after.tags.RunId -ne $runId) {
      throw "$($change.address) 的 key/checksum/metadata/tags plan 合同不完整。"
    }
  }

  $env:TF_VAR_release_id = 'wrong-current-release'
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $planPath)
  $env:TF_VAR_release_id = $oldRelease
  $contract = (& terraform "-chdir=$workDir" output -json release_contract) | ConvertFrom-Json -Depth 50
  if ($contract.release_id -ne $releaseId -or $contract.bucket -ne $bucket -or $contract.account_id -ne '000000000000') {
    throw 'saved plan 没有冻结 release_id 或 STS/bucket 输出错误。'
  }

  $buckets = Invoke-AwsJson @('s3api', 'list-buckets')
  if (@($buckets.Buckets | Where-Object { $_.Name -eq $bucket }).Count -ne 1) { throw '远端 release bucket 不唯一。' }
  $bucketTags = Invoke-AwsJson @('s3api', 'get-bucket-tagging', '--bucket', $bucket)
  Assert-Tag @($bucketTags.TagSet) 'RunId' $runId 'bucket'
  $listed = Invoke-AwsJson @('s3api', 'list-objects-v2', '--bucket', $bucket)
  $expectedKeys = @($contract.artifacts.PSObject.Properties.Value | ForEach-Object { $_.key } | Sort-Object)
  $actualKeys = @($listed.Contents | ForEach-Object { $_.Key } | Sort-Object)
  if (($actualKeys -join ',') -ne ($expectedKeys -join ',')) { throw '远端对象 keys 与发布合同不一致。' }
  foreach ($property in $contract.artifacts.PSObject.Properties) {
    $id = $property.Name; $artifact = $property.Value; $download = Join-Path $tempRoot "$id.download"
    [void](Invoke-AwsJson @('s3api', 'get-object', '--bucket', $bucket, '--key', $artifact.key, $download))
    $sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $download).Hash.ToLowerInvariant()
    $head = Invoke-AwsJson @('s3api', 'head-object', '--bucket', $bucket, '--key', $artifact.key)
    $tags = Invoke-AwsJson @('s3api', 'get-object-tagging', '--bucket', $bucket, '--key', $artifact.key)
    if ($sha -ne $artifact.checksum -or $head.ContentType -ne $artifact.content_type -or
      $head.Metadata.releaseid -ne $releaseId -or $head.Metadata.artifactid -ne $id -or $head.Metadata.owner -ne $artifact.owner -or $head.Metadata.runid -ne $runId) {
      throw "$id 的远端 bytes/content-type/metadata 不匹配。"
    }
    Assert-Tag @($tags.TagSet) 'RunId' $runId "object $id"
    Assert-Tag @($tags.TagSet) 'ArtifactId' $id "object $id"
  }

  $reorder = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color', '-var=manifest_path=../fixtures/manifest-reordered.json') + $commonVars) @(0, 2)
  if ($reorder -ne 0) { throw 'manifest 重排必须为零变更。' }
  $driftFile = Join-Path $tempRoot 'drift.txt'; Set-Content -LiteralPath $driftFile -Value 'out-of-band drift' -NoNewline
  [void](Invoke-AwsJson @('s3api', 'put-object', '--bucket', $bucket, '--key', 'services/api/config.json', '--body', $driftFile, '--content-type', 'text/plain'))
  $driftPlan = Join-Path $workDir 'drift.tfplan'
  $drift = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', "-out=$driftPlan", '-input=false', '-no-color') + $commonVars) @(0, 2)
  if ($drift -ne 2) { throw '远端对象漂移必须产生 exit 2。' }
  $driftJson = (& terraform "-chdir=$workDir" show -json $driftPlan) | ConvertFrom-Json -Depth 100
  if ($LASTEXITCODE -ne 0) { throw '无法读取 drift plan JSON。' }
  $driftChanges = @($driftJson.resource_changes | Where-Object { $_.mode -eq 'managed' -and (@($_.change.actions) -join ',') -ne 'no-op' })
  if ($driftChanges.Count -ne 1 -or $driftChanges[0].address -ne 'aws_s3_object.artifact["api-config"]' -or
    (@($driftChanges[0].change.actions) -join ',') -ne 'update') {
    throw 'drift plan 必须精确包含 api-config 对象的一次原地 update，禁止 delete/replace 或旁路变化。'
  }
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $driftPlan)
  $restored = Join-Path $tempRoot 'restored.json'
  [void](Invoke-AwsJson @('s3api', 'get-object', '--bucket', $bucket, '--key', 'services/api/config.json', $restored))
  if ((Get-FileHash -Algorithm SHA256 $restored).Hash.ToLowerInvariant() -ne $contract.artifacts.'api-config'.checksum) { throw '漂移恢复后的对象 bytes 不正确。' }
  $clean = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $commonVars) @(0, 2)
  if ($clean -ne 0) { throw '漂移恢复后必须是 clean plan。' }
  Invoke-Terraform $workDir (@('destroy', '-auto-approve', '-input=false', '-no-color') + $commonVars)
  $remaining = Invoke-AwsJson @('s3api', 'list-buckets')
  if (@($remaining.Buckets | Where-Object { $_.Name -eq $bucket }).Count -ne 0) { throw 'destroy 后 bucket 仍存在。' }
  Write-Host 'PASS: Challenge 36 精确 12/12 tests；LocalStack 1 S3 bucket + 3 objects，saved plan、远端内容/metadata、reorder、drift 恢复、clean/destroy 与零残留通过。'
}
finally {
  $cleanupFailure = $null
  $env:TF_VAR_release_id = $oldRelease
  if ($remoteMutationStarted -and (Test-Path $workDir) -and (Test-Path (Join-Path $workDir 'terraform.tfstate'))) {
    try { & terraform "-chdir=$workDir" destroy -auto-approve -input=false -no-color @commonVars 2>$null | Out-Null } catch { }
  }
  if ($remoteMutationStarted) {
    try {
      & aws --endpoint-url $LocalstackEndpoint --region us-east-1 s3 rb "s3://$bucket" --force 2>$null | Out-Null
      $remainingJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 s3api list-buckets --output json 2>&1)
      if ($LASTEXITCODE -ne 0) { throw "finally 无法列出 buckets：$($remainingJson -join "`n")" }
      $remainingBuckets = @(($remainingJson -join "`n" | ConvertFrom-Json -Depth 20).Buckets | Where-Object { $_.Name -eq $bucket })
      if ($remainingBuckets.Count -ne 0) { throw "finally 清理后本 run bucket 仍存在：$bucket" }
    }
    catch { $cleanupFailure = $_.Exception.Message }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess; $env:AWS_SECRET_ACCESS_KEY = $oldSecret; $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
  if ($null -ne $cleanupFailure) { throw "Challenge 36 finally 清理失败：$cleanupFailure" }
}
