[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "..\starter"),
  [string]$LocalstackEndpoint = "http://localhost:4566",
  [switch]$SkipE2E
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-LoopbackEndpoint([string]$Endpoint) {
  $rawPattern = '\Ahttps?://(?:localhost|127\.0\.0\.1|\[::1\]):[1-9][0-9]{0,4}\z'
  if (-not [regex]::IsMatch($Endpoint, $rawPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) { throw "拒绝不规范、无显式端口或非 loopback endpoint：$Endpoint" }
  try { $uri = [Uri]$Endpoint } catch { throw "LocalStack endpoint 不是合法 URI：$Endpoint" }
  if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http', 'https') -or $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or
    $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535 -or
    $Endpoint -match '(?i)%2e|%2f|%5c|\\') { throw "拒绝包含凭证、路径、查询、fragment 或归一化绕过的 endpoint：$Endpoint" }
}

function Remove-HclComments([string]$Text) {
  $builder = [Text.StringBuilder]::new($Text.Length); $state = 'code'
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $c = $Text[$i]; $n = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
    if ($state -eq 'code') {
      if ($c -eq '"') { [void]$builder.Append($c); $state = 'string' }
      elseif ($c -eq '#') { [void]$builder.Append(' '); $state = 'line' }
      elseif ($c -eq '/' -and $n -eq '/') { [void]$builder.Append('  '); $i++; $state = 'line' }
      elseif ($c -eq '/' -and $n -eq '*') { [void]$builder.Append('  '); $i++; $state = 'block' }
      else { [void]$builder.Append($c) }
    } elseif ($state -eq 'string') {
      [void]$builder.Append($c)
      if ($c -eq '\' -and $i + 1 -lt $Text.Length) { $i++; [void]$builder.Append($Text[$i]) } elseif ($c -eq '"') { $state = 'code' }
    } elseif ($state -eq 'line') {
      if ($c -eq "`n") { [void]$builder.Append($c); $state = 'code' } else { [void]$builder.Append(' ') }
    } else {
      if ($c -eq '*' -and $n -eq '/') { [void]$builder.Append('  '); $i++; $state = 'code' }
      elseif ($c -eq "`n") { [void]$builder.Append($c) } else { [void]$builder.Append(' ') }
    }
  }
  $builder.ToString()
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
    $open = $Text.IndexOf('{', $match.Index); if ($open -lt 0) { continue }
    $depth = 0; $inString = $false
    for ($i = $open; $i -lt $Text.Length; $i++) {
      $c = $Text[$i]
      if ($inString) { if ($c -eq '\') { $i++; continue }; if ($c -eq '"') { $inString = $false }; continue }
      if ($c -eq '"') { $inString = $true; continue }
      if ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $blocks.Add($Text.Substring($match.Index, $i - $match.Index + 1)); break } }
    }
  }
  return @($blocks)
}

function Assert-OneBlock([string]$Text, [string]$Pattern, [string]$Context) {
  $blocks = @(Get-HclBlocks $Text $Pattern); if ($blocks.Count -ne 1) { throw "$Context 必须精确出现一次。" }; $blocks[0]
}

function Assert-Assignment([string]$Block, [string]$Name, [string]$Pattern, [string]$Context) {
  if ([regex]::Matches($Block, "(?m)^\s*$([regex]::Escape($Name))\s*=\s*$Pattern\s*$").Count -ne 1) { throw "$Context 必须精确设置 $Name。" }
}

function Get-ConditionExpression([string]$Block, [string]$Context) {
  if ([regex]::Matches($Block, '(?m)^\s*condition\s*=').Count -ne 1) { throw "$Context 必须且只能声明一个 condition。" }
  $match = [regex]::Match($Block, '(?ms)^\s*condition\s*=\s*(.*?)^\s*error_message\s*=')
  if (-not $match.Success) { throw "$Context condition/error_message 结构不可审计。" }
  return $match.Groups[1].Value.Trim()
}

function Copy-CleanTree([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Where-Object { $_.Name -notin @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup', '.terraform.tfstate.lock.info', 'tests-generated') -and $_.Extension -ne '.tfplan' } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
  }
}

function Invoke-Tf([string]$Dir, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  $out = @(& terraform "-chdir=$Dir" @Arguments 2>&1); $code = $LASTEXITCODE; $out | Out-Host
  if ($code -notin $Allowed) { throw "terraform $($Arguments -join ' ') 失败，exit=$code" }; return @{ Code = $code; Text = ($out -join "`n") }
}

function Invoke-ExactTests([string]$Dir, [int]$Expected) {
  $r = Invoke-Tf $Dir @('test', '-test-directory=tests-generated', '-no-color')
  if ([regex]::Matches($r.Text, "(?m)^Success!\s+$Expected passed,\s+0 failed\.\s*$").Count -ne 1 -or
    [regex]::Matches($r.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne $Expected) { throw "canonical tests 必须精确通过 $Expected runs。" }
}

# 原始 endpoint 必须在读取 Candidate、健康检查或任何网络调用之前验证。
Assert-LoopbackEndpoint $LocalstackEndpoint

$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$modulePath = Join-Path $candidatePath 'modules\diagnostics'
if (-not (Test-Path -LiteralPath $modulePath -PathType Container)) { throw '缺少 modules/diagnostics。' }
$tfFiles = @(Get-AllowedTfFiles $candidatePath @('.', 'modules\diagnostics') 'Challenge 38')
$trim = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$rootFull = [IO.Path]::GetFullPath($candidatePath).TrimEnd($trim); $moduleFull = [IO.Path]::GetFullPath($modulePath).TrimEnd($trim)
$rootFiles = @($tfFiles | Where-Object { [string]::Equals([IO.Path]::GetFullPath($_.DirectoryName).TrimEnd($trim), $rootFull, [StringComparison]::OrdinalIgnoreCase) })
$moduleFiles = @($tfFiles | Where-Object { [string]::Equals([IO.Path]::GetFullPath($_.DirectoryName).TrimEnd($trim), $moduleFull, [StringComparison]::OrdinalIgnoreCase) })
Assert-ExactTopLevelBlocks $rootFiles @(
  'terraform', 'provider:aws', 'provider:aws',
  'variable:primary_region', 'variable:dr_region', 'variable:localstack_endpoint', 'variable:run_id', 'variable:ami_name_pattern',
  'module:diagnostics',
  'output:diagnostic_contract', 'output:vpc_contract', 'output:supply_chain_contract'
) 'Challenge 38 root'
Assert-ExactTopLevelBlocks $moduleFiles @(
  'terraform',
  'variable:primary_region', 'variable:dr_region', 'variable:run_id', 'variable:ami_name_pattern',
  'data:aws_ami:primary', 'data:aws_caller_identity:primary', 'data:aws_iam_session_context:primary',
  'data:aws_ami:dr', 'data:aws_caller_identity:dr', 'data:aws_iam_session_context:dr',
  'resource:aws_vpc:primary', 'resource:aws_vpc:dr', 'locals',
  'output:diagnostic_contract', 'output:vpc_contract'
) 'Challenge 38 child modules/diagnostics'
$rootText = Remove-HclComments (($rootFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n")
$moduleText = Remove-HclComments (($moduleFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n")
$allText = "$rootText`n$moduleText"

$endpointVar = Assert-OneBlock $rootText '(?m)^\s*variable\s+"localstack_endpoint"\s*\{' 'localstack_endpoint variable'
Assert-Assignment $endpointVar 'default' '"http://localhost:4566"' 'localstack_endpoint'
$endpointValidations = @(Get-HclBlocks $endpointVar '(?m)^\s*validation\s*\{')
if ($endpointValidations.Count -ne 1) { throw 'localstack_endpoint 必须且只能有一个严格 validation。' }
$endpointCondition = Get-ConditionExpression $endpointValidations[0] 'localstack_endpoint validation'
foreach ($literal in @('localhost', '127\\.0\\.0\\.1', '\\[::1\\]', '[1-9][0-9]{0,4}', '\\z')) {
  if (-not $endpointCondition.Contains($literal)) { throw "localstack_endpoint validation 缺少精确 loopback/port literal：$literal" }
}
foreach ($pattern in @('regex\s*\(', 'tonumber\s*\(', '<=\s*65535')) {
  if ($endpointCondition -notmatch $pattern) { throw "localstack_endpoint validation 缺少实质边界：$pattern" }
}
$providers = @(Get-HclBlocks $rootText '(?m)^\s*provider\s+"aws"\s*\{')
if ($providers.Count -ne 2) { throw 'root 必须且只能声明两个 AWS provider。' }
$default = @($providers | Where-Object { $_ -notmatch '(?m)^\s*alias\s*=' })
$dr = @($providers | Where-Object { [regex]::Matches($_, '(?m)^\s*alias\s*=\s*"dr"\s*$').Count -eq 1 })
if ($default.Count -ne 1 -or $dr.Count -ne 1) { throw 'provider slots 必须精确为 default 与 aws.dr。' }
foreach ($entry in @(@{ Block = $default[0]; Region = 'var\.primary_region'; Name = 'default' }, @{ Block = $dr[0]; Region = 'var\.dr_region'; Name = 'dr' })) {
  Assert-Assignment $entry.Block 'region' $entry.Region $entry.Name
  Assert-Assignment $entry.Block 'access_key' '"test"' $entry.Name
  Assert-Assignment $entry.Block 'secret_key' '"test"' $entry.Name
  foreach ($flag in @('skip_credentials_validation', 'skip_metadata_api_check', 'skip_requesting_account_id')) { Assert-Assignment $entry.Block $flag 'true' $entry.Name }
  $ep = Assert-OneBlock $entry.Block '(?m)^\s*endpoints\s*\{' "$($entry.Name) endpoints"
  $keys = @([regex]::Matches($ep, '(?m)^\s*([a-z0-9_]+)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  if (($keys -join ',') -ne 'ec2,iam,sts') { throw "$($entry.Name) endpoints 必须精确为 ec2,iam,sts。" }
  foreach ($service in @('ec2', 'iam', 'sts')) { Assert-Assignment $ep $service 'var\.localstack_endpoint' "$($entry.Name) endpoints" }
}
if ($allText -match '(?i)(profile\s*=|(?m)^\s*token\s*=|shared_(config|credentials)|assume_role(_with_web_identity)?\s*\{|web_identity_token|credential_process|AKIA[0-9A-Z]{16})') { throw '检测到可绕过 LocalStack 的凭证渠道。' }
if ([regex]::Matches($rootText, 'required_version\s*=\s*"~>\s*1\.6"').Count -ne 1 -or [regex]::Matches($moduleText, 'required_version\s*=\s*"~>\s*1\.6"').Count -ne 1) { throw 'root 与 child 都必须使用 Terraform ~> 1.6。' }
if ($rootText -notmatch 'version\s*=\s*"~>\s*5\.100"' -or $moduleText -notmatch 'version\s*=\s*">=\s*5\.100,\s*<\s*6\.0"' -or $moduleText -notmatch 'configuration_aliases\s*=\s*\[\s*aws\.dr\s*\]') { throw 'provider 约束交集或 configuration_aliases 错误。' }
$moduleCall = Assert-OneBlock $rootText '(?m)^\s*module\s+"diagnostics"\s*\{' 'module.diagnostics'
Assert-Assignment $moduleCall 'aws' 'aws' 'module providers map'
Assert-Assignment $moduleCall 'aws.dr' 'aws\.dr' 'module providers map'
foreach ($type in @('aws_ami', 'aws_caller_identity', 'aws_iam_session_context')) {
  [void](Assert-OneBlock $moduleText "(?m)^\s*data\s+`"$type`"\s+`"primary`"\s*\{" "data.$type.primary")
  $block = Assert-OneBlock $moduleText "(?m)^\s*data\s+`"$type`"\s+`"dr`"\s*\{" "data.$type.dr"
  Assert-Assignment $block 'provider' 'aws\.dr' "data.$type.dr"
}
foreach ($slot in @('primary', 'dr')) {
  $block = Assert-OneBlock $moduleText "(?m)^\s*resource\s+`"aws_vpc`"\s+`"$slot`"\s*\{" "aws_vpc.$slot"
  if ($slot -eq 'dr') { Assert-Assignment $block 'provider' 'aws\.dr' 'aws_vpc.dr' }
  if ($block -notmatch 'RunId\s*=\s*var\.run_id') { throw "aws_vpc.$slot 缺少 RunId 标签。" }
}
$guard = Assert-OneBlock $rootText '(?m)^\s*output\s+"diagnostic_contract"\s*\{' 'diagnostic_contract guard'
$preconditions = @(Get-HclBlocks $guard '(?m)^\s*precondition\s*\{')
if ($preconditions.Count -ne 4) { throw 'contract_guard 必须精确包含四个 precondition。' }
$semanticPatterns = [ordered]@{
  region = @(
    'module\.diagnostics\.diagnostic_contract\.primary\.region\s*==\s*var\.primary_region',
    'module\.diagnostics\.diagnostic_contract\.dr\.region\s*==\s*var\.dr_region',
    'var\.primary_region\s*!=\s*var\.dr_region'
  )
  ami = @(
    'can\s*\(\s*regex\s*\(\s*"\^ami-\[0-9a-f\]\{8,17\}\$"\s*,\s*module\.diagnostics\.diagnostic_contract\.primary\.ami_id\s*\)\s*\)',
    'can\s*\(\s*regex\s*\(\s*"\^ami-\[0-9a-f\]\{8,17\}\$"\s*,\s*module\.diagnostics\.diagnostic_contract\.dr\.ami_id\s*\)\s*\)'
  )
  account = @(
    'can\s*\(\s*regex\s*\(\s*"\^\[0-9\]\{12\}\$"\s*,\s*module\.diagnostics\.diagnostic_contract\.primary\.account_id\s*\)\s*\)',
    'can\s*\(\s*regex\s*\(\s*"\^\[0-9\]\{12\}\$"\s*,\s*module\.diagnostics\.diagnostic_contract\.dr\.account_id\s*\)\s*\)'
  )
  issuer = @(
    'module\.diagnostics\.diagnostic_contract\.primary\.issuer_arn\s*!=\s*""',
    'startswith\s*\(\s*module\.diagnostics\.diagnostic_contract\.primary\.issuer_arn\s*,\s*"arn:aws:iam::\$\{module\.diagnostics\.diagnostic_contract\.primary\.account_id\}:"\s*\)',
    'module\.diagnostics\.diagnostic_contract\.dr\.issuer_arn\s*!=\s*""',
    'startswith\s*\(\s*module\.diagnostics\.diagnostic_contract\.dr\.issuer_arn\s*,\s*"arn:aws:iam::\$\{module\.diagnostics\.diagnostic_contract\.dr\.account_id\}:"\s*\)'
  )
}
$matchedSemantics = [Collections.Generic.List[string]]::new()
foreach ($block in $preconditions) {
  $expression = Get-ConditionExpression $block 'diagnostic_contract precondition'
  $semanticMatches = @()
  foreach ($semantic in $semanticPatterns.Keys) {
    if (@($semanticPatterns[$semantic] | Where-Object { $expression -notmatch $_ }).Count -eq 0) { $semanticMatches += $semantic }
  }
  if ($semanticMatches.Count -ne 1) { throw '每个 precondition 必须只实现 region/AMI/account/issuer 中的一类，并同时覆盖 primary 与 dr。' }
  $matchedSemantics.Add($semanticMatches[0])
}
if (($matchedSemantics | Sort-Object -Unique) -join ',' -ne 'account,ami,issuer,region') { throw '四类 precondition 必须各自精确出现一次，禁止 catch-all 或平凡 guard。' }

$tempBase = [IO.Path]::GetTempPath(); $runId = 'c38' + [Guid]::NewGuid().ToString('N').Substring(0, 9)
$temp = Join-Path $tempBase "tfpro-c38-$runId"; $work = Join-Path $temp 'candidate'; $conflict = Join-Path $temp 'conflict'
$oldAccess = $env:AWS_ACCESS_KEY_ID; $oldSecret = $env:AWS_SECRET_ACCESS_KEY; $oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'
$common = @("-var=localstack_endpoint=$LocalstackEndpoint", "-var=run_id=$runId")
$failure = $null; $e2eStarted = $false
try {
  Copy-CleanTree $candidatePath $work
  New-Item -ItemType Directory -Force -Path (Join-Path $work 'tests-generated') | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $work 'tests-generated\canonical.tftest.hcl')
  Invoke-Tf $work @('fmt', '-check', '-recursive') | Out-Null
  Invoke-Tf $work @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Invoke-Tf $work @('validate', '-no-color') | Out-Null
  Invoke-ExactTests $work 12

  $lock = Get-Content -Raw (Join-Path $work '.terraform.lock.hcl')
  if ($lock -notmatch 'provider "registry\.terraform\.io/hashicorp/aws"' -or $lock -notmatch 'version\s*=\s*"5\.100\.0"' -or [regex]::Matches($lock, 'h1:|zh:').Count -lt 1) { throw 'lockfile 必须锁定 AWS 5.100.0 并包含校验哈希。' }
  $providersText = (Invoke-Tf $work @('providers', '-no-color')).Text
  if ($providersText -notmatch 'module\.diagnostics' -or $providersText -notmatch '~>\s*5\.100' -or $providersText -notmatch '>=\s*5\.100(?:\.0)?,\s*<\s*6\.0(?:\.0)?') { throw 'terraform providers 未显示 root/child 约束依赖图。' }
  $schemaText = @(& terraform "-chdir=$work" providers schema -json 2>&1) -join "`n"
  if ($LASTEXITCODE) { throw "providers schema 失败：$schemaText" }
  $schema = $schemaText | ConvertFrom-Json -Depth 100
  $awsSchema = $schema.provider_schemas.'registry.terraform.io/hashicorp/aws'
  foreach ($name in @('aws_ami', 'aws_caller_identity', 'aws_iam_session_context')) { if ($null -eq $awsSchema.data_source_schemas.PSObject.Properties[$name]) { throw "provider schema 缺少 $name。" } }
  if ($null -eq $awsSchema.resource_schemas.PSObject.Properties['aws_vpc']) { throw 'provider schema 缺少 aws_vpc。' }

  Copy-CleanTree $candidatePath $conflict
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\fixtures\conflicting-module-versions.txt') -Destination (Join-Path $conflict 'modules\diagnostics\versions.tf') -Force
  $conflictOut = @(& terraform "-chdir=$conflict" init -backend=false -upgrade -input=false -no-color 2>&1); $conflictCode = $LASTEXITCODE; $conflictOut | Out-Host
  if ($conflictCode -eq 0 -or ($conflictOut -join "`n") -notmatch '(?i)(no available releases match|no available versions match|locked provider.*does not match|version constraints)') { throw '冲突 child provider 约束必须在 init 阶段清晰失败。' }

  if ($SkipE2E) { Write-Host 'PASS: Challenge 38 exact 12 tests + supply-chain static, lockfile, graph, schema and conflict audit.'; return }
  $health = Invoke-RestMethod -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5
  foreach ($svc in @('ec2', 'iam', 'sts')) { if ($health.services.$svc -notin @('available', 'running')) { throw "LocalStack $svc 不可用。" } }
  $e2eStarted = $true

  $planPath = Join-Path $work 'delivery.tfplan'; Invoke-Tf $work (@('plan', '-input=false', '-no-color', "-out=$planPath") + $common) | Out-Null
  $planRaw = @(& terraform "-chdir=$work" show -json $planPath 2>&1) -join "`n"; if ($LASTEXITCODE) { throw 'saved plan JSON 读取失败。' }
  $plan = $planRaw | ConvertFrom-Json -Depth 100
  $configs = $plan.configuration.provider_config
  if ($null -eq $configs.aws -or $null -eq $configs.'aws.dr' -or $configs.'aws.dr'.alias -ne 'dr') { throw 'plan JSON provider configs 不完整。' }
  $expected = Get-Content -Raw (Join-Path $PSScriptRoot '..\fixtures\expected-provider-addresses.json') | ConvertFrom-Json -AsHashtable
  $resources = @($plan.configuration.root_module.module_calls.diagnostics.module.resources)
  $actualConfigurationAddresses = @($resources | ForEach-Object { [string]$_.address } | Sort-Object)
  $expectedConfigurationAddresses = @($expected.Keys | Sort-Object)
  if (($actualConfigurationAddresses -join ',') -ne ($expectedConfigurationAddresses -join ',')) {
    throw "plan configuration 必须精确包含8个预期地址，禁止额外资源：$($actualConfigurationAddresses -join ', ')"
  }
  foreach ($pair in $expected.GetEnumerator()) {
    $found = @($resources | Where-Object { $_.address -eq $pair.Key })
    if ($found.Count -ne 1 -or $found[0].provider_config_key -ne $pair.Value) { throw "$($pair.Key) provider_config_key 应为 $($pair.Value)。" }
  }
  $planChanges = @($plan.resource_changes)
  $managedChanges = @($planChanges | Where-Object { $_.mode -eq 'managed' })
  $expectedManaged = @('module.diagnostics.aws_vpc.dr', 'module.diagnostics.aws_vpc.primary') | Sort-Object
  if ($planChanges.Count -ne 2 -or (@($managedChanges | ForEach-Object { [string]$_.address } | Sort-Object) -join ',') -ne ($expectedManaged -join ',') -or
    @($managedChanges | Where-Object { (@($_.change.actions) -join ',') -ne 'create' }).Count -ne 0) {
    throw 'saved plan resource_changes 必须精确为 primary/dr 两个 managed VPC，且 actions 全为 create；六个 data source 已在 plan 前读取并由8地址 configuration graph审计。'
  }
  Invoke-Tf $work @('apply', '-input=false', '-no-color', $planPath) | Out-Null
  $diagnosticRaw = @(& terraform "-chdir=$work" output -json diagnostic_contract 2>&1) -join "`n"; if ($LASTEXITCODE) { throw '无法读取真实 diagnostic_contract。' }
  $diagnostic = $diagnosticRaw | ConvertFrom-Json -Depth 20
  if ($diagnostic.primary.region -ne 'us-east-1' -or $diagnostic.dr.region -ne 'us-west-2') { throw '真实 diagnostic_contract 区域错误。' }
  foreach ($slot in @('primary', 'dr')) {
    $item = $diagnostic.$slot
    if ($item.ami_id -notmatch '^ami-[0-9a-f]{8,17}$' -or $item.account_id -ne '000000000000' -or $item.issuer_arn -notmatch '^arn:aws:iam::000000000000:') { throw "真实 $slot AMI/account/issuer 诊断错误。" }
  }
  $vpcContractRaw = @(& terraform "-chdir=$work" output -json vpc_contract 2>&1) -join "`n"; if ($LASTEXITCODE) { throw '无法读取真实 vpc_contract。' }
  $vpcContract = $vpcContractRaw | ConvertFrom-Json -Depth 20
  $expectedVpcSlots = @(
    @{ Slot = 'primary'; Region = 'us-east-1'; Name = "$runId-primary"; Cidr = '10.38.0.0/24' },
    @{ Slot = 'dr'; Region = 'us-west-2'; Name = "$runId-dr"; Cidr = '10.38.1.0/24' }
  )
  foreach ($entry in $expectedVpcSlots) {
    $raw = @(& aws --endpoint-url $LocalstackEndpoint --region $entry.Region ec2 describe-vpcs --filters "Name=tag:Name,Values=$($entry.Name)" --output json 2>&1) -join "`n"; if ($LASTEXITCODE) { throw $raw }
    $vpcs = ($raw | ConvertFrom-Json).Vpcs
    $contractSlot = $vpcContract.($entry.Slot)
    if (@($vpcs).Count -ne 1 -or (@($vpcs[0].Tags | Where-Object { $_.Key -eq 'RunId' }).Value) -ne $runId -or
      $vpcs[0].CidrBlock -ne $entry.Cidr -or $contractSlot.id -ne $vpcs[0].VpcId -or $contractSlot.cidr -ne $entry.Cidr) {
      throw "真实 $($entry.Slot) VPC 的 region/ID/CIDR/RunId 合同不精确。"
    }
  }
  $clean = Invoke-Tf $work (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $common) @(0, 2)
  if ($clean.Code -ne 0) { throw 'apply 后必须是 clean plan。' }
  Invoke-Tf $work (@('destroy', '-auto-approve', '-input=false', '-no-color') + $common) | Out-Null
} catch { $failure = $_ } finally {
  $cleanupFailures = [Collections.Generic.List[string]]::new()
  if ($e2eStarted) {
    if ((Test-Path $work) -and (Test-Path (Join-Path $work 'terraform.tfstate'))) {
      $destroyOutput = @(& terraform "-chdir=$work" destroy -auto-approve -input=false -no-color @common 2>&1)
      if ($LASTEXITCODE -ne 0) { $cleanupFailures.Add("finally terraform destroy exit=$LASTEXITCODE：$($destroyOutput -join "`n")") }
    }
    foreach ($region in @('us-east-1', 'us-west-2')) {
      $describeOutput = @(& aws --endpoint-url $LocalstackEndpoint --region $region ec2 describe-vpcs --filters "Name=tag:RunId,Values=$runId" --output json 2>&1)
      if ($LASTEXITCODE -ne 0) {
        $cleanupFailures.Add("$region CLI 兜底 describe 失败：$($describeOutput -join "`n")")
        continue
      }
      foreach ($vpc in @(($describeOutput -join "`n" | ConvertFrom-Json -Depth 30).Vpcs)) {
        $deleteOutput = @(& aws --endpoint-url $LocalstackEndpoint --region $region ec2 delete-vpc --vpc-id $vpc.VpcId 2>&1)
        if ($LASTEXITCODE -ne 0) { $cleanupFailures.Add("$region CLI 兜底删除 $($vpc.VpcId) 失败：$($deleteOutput -join "`n")") }
      }
      $verifyOutput = @(& aws --endpoint-url $LocalstackEndpoint --region $region ec2 describe-vpcs --filters "Name=tag:RunId,Values=$runId" --output json 2>&1)
      if ($LASTEXITCODE -ne 0) {
        $cleanupFailures.Add("$region 最终残留验证失败：$($verifyOutput -join "`n")")
      }
      elseif (@(($verifyOutput -join "`n" | ConvertFrom-Json -Depth 30).Vpcs).Count -ne 0) {
        $cleanupFailures.Add("$region 最终仍有 RunId=$runId VPC 残留。")
      }
    }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess; $env:AWS_SECRET_ACCESS_KEY = $oldSecret; $env:AWS_DEFAULT_REGION = $oldRegion
  $resolved = [IO.Path]::GetFullPath($temp)
  if ($resolved.StartsWith([IO.Path]::GetFullPath($tempBase), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'tfpro-c38-*') {
    if (Test-Path $resolved) {
      try { Remove-Item -LiteralPath $resolved -Recurse -Force }
      catch { $cleanupFailures.Add("临时目录清理失败：$($_.Exception.Message)") }
    }
  }
  else { $cleanupFailures.Add('拒绝删除不安全的临时目录。') }
  if ($cleanupFailures.Count -gt 0) {
    $cleanupMessage = $cleanupFailures -join ' | '
    if ($failure) { $failure = [Exception]::new("原始失败：$failure；清理失败：$cleanupMessage") }
    else { $failure = [Exception]::new("清理失败：$cleanupMessage") }
  }
}
if ($failure) { throw $failure }
Write-Host 'PASS: Challenge 38 exact 12 tests + init/lock/schema/conflict + exact 8-address plan routing + dual-region VPC ID/CIDR + zero-residual cleanup.'
