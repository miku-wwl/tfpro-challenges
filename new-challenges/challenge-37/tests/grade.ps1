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
  if (-not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri)) { throw 'LocalstackEndpoint 必须是绝对 URI。' }
  $hostName = $uri.Host.Trim('[', ']').ToLowerInvariant()
  if ($uri.Scheme -notin @('http', 'https') -or $hostName -notin @('localhost', '127.0.0.1', '::1') -or
    -not [string]::IsNullOrEmpty($uri.UserInfo) -or $uri.AbsolutePath -ne '/' -or
    -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw 'LocalstackEndpoint 仅允许 loopback HTTP(S) 根地址。'
  }
}

function Remove-HclComments([string]$Text) {
  $builder = [Text.StringBuilder]::new($Text.Length); $state = 'code'
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $current = $Text[$i]; $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
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
    $open = $Text.IndexOf('{', $match.Index); if ($open -lt 0) { continue }
    $depth = 0; $inString = $false
    for ($i = $open; $i -lt $Text.Length; $i++) {
      $current = $Text[$i]
      if ($inString) { if ($current -eq '\') { $i++; continue }; if ($current -eq '"') { $inString = $false }; continue }
      if ($current -eq '"') { $inString = $true; continue }
      if ($current -eq '{') { $depth++ }
      elseif ($current -eq '}') { $depth--; if ($depth -eq 0) { $blocks.Add($Text.Substring($match.Index, $i - $match.Index + 1)); break } }
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
  if ($variables.Count -ne 1 -or -not (Test-ExactAssignment $variables[0] 'default' '"http://localhost:4566"')) { throw 'localstack_endpoint variable 必须唯一且默认值精确。' }
  $validations = @(Get-HclBlocks $variables[0] '(?m)^\s*validation\s*\{')
  if ($validations.Count -ne 1 -or $validations[0] -notmatch '\\\\z') { throw 'localstack_endpoint 必须使用整串 \\z loopback validation。' }
  $providers = @(Get-HclBlocks $safe '(?m)^\s*provider\s+"aws"\s*\{')
  if ($providers.Count -ne 1) { throw '必须且只能有一个 aws provider block。' }
  $provider = $providers[0]
  $required = [ordered]@{
    region = 'var\.aws_region'; access_key = '"test"'; secret_key = '"test"'
    skip_credentials_validation = 'true'; skip_metadata_api_check = 'true'; skip_requesting_account_id = 'true'
  }
  foreach ($entry in $required.GetEnumerator()) { if (-not (Test-ExactAssignment $provider $entry.Key $entry.Value)) { throw "provider 必须精确设置 $($entry.Key)。" } }
  $endpoints = @(Get-HclBlocks $provider '(?m)^\s*endpoints\s*\{')
  if ($endpoints.Count -ne 1) { throw '必须且只能有一个 endpoints block。' }
  $keys = @([regex]::Matches($endpoints[0], '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
  if (($keys -join ',') -ne 'ec2,sts') { throw 'endpoints 必须精确包含 ec2、sts。' }
  foreach ($service in @('ec2', 'sts')) { if (-not (Test-ExactAssignment $endpoints[0] $service 'var\.localstack_endpoint')) { throw "$service endpoint 必须引用 var.localstack_endpoint。" } }
  if ($safe -match '(?im)^\s*(?:profile|token|shared_config_files|shared_credentials_files|web_identity_token_file)\s*=|shared_credentials|^\s*assume_role(?:_with_web_identity)?\s*\{|AKIA[0-9A-Z]{16}') { throw '禁止替代凭证源、AssumeRole 或疑似真实 AWS key。' }
}

function Assert-SourceContract([string]$Source) {
  $safe = Remove-HclComments $Source
  $checks = @('rules_not_empty', 'rule_ids_unique', 'rule_keys_unique', 'rule_ranges_nonoverlapping', 'rule_ids_valid', 'rule_directions_valid', 'rule_protocols_valid', 'rule_descriptions_valid', 'rule_enabled_values_valid', 'rule_ports_valid', 'rule_cidrs_valid')
  foreach ($name in $checks) { if (@(Get-HclBlocks $safe "(?m)^\s*check\s+`"$name`"\s*\{").Count -ne 1) { throw "缺少唯一 check.$name。" } }
  foreach ($pattern in @(
      'data\s+"aws_caller_identity"\s+"current"\s*\{', 'data\s+"aws_vpc"\s+"selected"\s*\{', 'data\s+"aws_security_group"\s+"selected"\s*\{',
      'resource\s+"aws_vpc"\s+"rules"\s*\{', 'resource\s+"aws_security_group"\s+"compiled"\s*\{',
      'resource\s+"aws_vpc_security_group_ingress_rule"\s+"compiled"\s*\{', 'resource\s+"aws_vpc_security_group_egress_rule"\s+"compiled"\s*\{'
    )) { if ([regex]::Matches($safe, $pattern).Count -ne 1) { throw "结构缺失或重复：$pattern" } }
  foreach ($pattern in @(
      'csvdecode\(file\(var\.rules_csv_path\)\)',
      'format\("%s\|%s\|%05d-%05d\|%s"',
      'rule\.rule_id\s*=>\s*rule\.\.\.',
      'rule\.rule_key\s*=>\s*rule\.\.\.',
      'alltrue\(local\.overlap_matrix\)',
      'left\.to_port\s*<\s*right\.from_port',
      'contains\(\["ingress",\s*"egress"\],\s*group\[0\]\.direction\)',
      'contains\(\["tcp",\s*"udp",\s*"-1"\],\s*group\[0\]\.protocol\)',
      'can\(cidrnetmask\(group\[0\]\.cidr\)\)',
      'for_each\s*=\s*local\.ingress_rules', 'for_each\s*=\s*local\.egress_rules',
      'security_group_id\s*=\s*aws_security_group\.compiled\.id',
      'cidr_ipv4\s*=\s*each\.value\.cidr', 'RunId\s*=\s*var\.run_id'
    )) { if ($safe -notmatch $pattern) { throw "实现合同缺少实质表达式：$pattern" } }
  $sgBlocks = @(Get-HclBlocks $safe '(?m)^\s*resource\s+"aws_security_group"\s+"compiled"\s*\{')
  if ($sgBlocks[0] -match '(?m)^\s*(?:ingress|egress)\s*\{') { throw 'Security Group 禁止内联规则。' }
  if ($safe -match '(?m)^\s*count\s*=|ignore_changes\s*=') { throw '禁止 count 身份或 ignore_changes 绕过漂移。' }
}

function Copy-CleanTree([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Where-Object { $_.Name -notin @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force }
}

function Invoke-Terraform([string]$Directory, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0)) {
  & terraform "-chdir=$Directory" @Arguments | Out-Host; $code = $LASTEXITCODE
  if ($code -notin $AllowedExitCodes) { throw "terraform $($Arguments -join ' ') 失败，exit=$code" }; return $code
}

function Invoke-ExactTests([string]$Directory, [int]$Expected) {
  $output = @(& terraform "-chdir=$Directory" test -test-directory=tests -no-color 2>&1); $code = $LASTEXITCODE; $output | Out-Host; $text = $output -join "`n"
  $summary = [regex]::Matches($text, '(?m)^Success!\s+([0-9]+) passed,\s+0 failed\.\s*$'); $runs = [regex]::Matches($text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$')
  if ($code -ne 0 -or $summary.Count -ne 1 -or [int]$summary[0].Groups[1].Value -ne $Expected -or $runs.Count -ne $Expected) { throw "canonical tests 必须精确通过 $Expected/$Expected。" }
}

function Invoke-AwsJson([string[]]$Arguments) {
  $output = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 @Arguments --output json 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "aws $($Arguments -join ' ') 失败：$($output -join "`n")" }
  $text = $output -join "`n"; if ([string]::IsNullOrWhiteSpace($text)) { return $null }; return ($text | ConvertFrom-Json -Depth 100)
}

function Assert-Tag([object[]]$Tags, [string]$Key, [string]$Value, [string]$Label) {
  $matches = @($Tags | Where-Object { $_.Key -eq $Key }); if ($matches.Count -ne 1 -or $matches[0].Value -ne $Value) { throw "$Label 缺少唯一 $Key=$Value tag。" }
}

Assert-LoopbackEndpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tfFiles = @(Get-AllowedTfFiles $candidatePath @('.') 'Challenge 37')
Assert-ExactTopLevelBlocks $tfFiles @(
  'terraform', 'provider:aws',
  'variable:aws_region', 'variable:localstack_endpoint', 'variable:name_prefix', 'variable:run_id', 'variable:vpc_cidr', 'variable:rules_csv_path',
  'data:aws_caller_identity:current', 'data:aws_vpc:selected', 'data:aws_security_group:selected', 'locals',
  'check:rules_not_empty', 'check:rule_ids_unique', 'check:rule_keys_unique', 'check:rule_ranges_nonoverlapping', 'check:rule_ids_valid', 'check:rule_directions_valid', 'check:rule_protocols_valid', 'check:rule_descriptions_valid', 'check:rule_enabled_values_valid', 'check:rule_ports_valid', 'check:rule_cidrs_valid',
  'resource:aws_vpc:rules', 'resource:aws_security_group:compiled', 'resource:aws_vpc_security_group_ingress_rule:compiled', 'resource:aws_vpc_security_group_egress_rule:compiled',
  'output:active_rule_keys', 'output:resource_addresses', 'output:security_contract'
) 'Challenge 37 root'
$source = ($tfFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
Assert-AwsProviderContract $source
Assert-SourceContract $source

$suffix = ([Guid]::NewGuid().ToString('N')).Substring(0, 10); $tempRoot = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c37-$suffix"; $workDir = Join-Path $tempRoot 'candidate'
$namePrefix = "c37-$suffix"; $runId = "run-$suffix"; $commonVars = @("-var=name_prefix=$namePrefix", "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
$oldAccess = $env:AWS_ACCESS_KEY_ID; $oldSecret = $env:AWS_SECRET_ACCESS_KEY; $oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $remoteMutationStarted = $false

try {
  Copy-CleanTree $candidatePath $workDir
  Copy-Item -LiteralPath (Join-Path $labRoot 'fixtures') -Destination (Join-Path $tempRoot 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $workDir 'tests') | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $workDir 'tests\canonical.tftest.hcl') -Force
  Invoke-Terraform $workDir @('fmt', '-check', '-recursive'); Invoke-Terraform $workDir @('init', '-backend=false', '-input=false', '-no-color'); Invoke-Terraform $workDir @('validate', '-no-color'); Invoke-ExactTests $workDir 14
  if ($SkipE2E) { Write-Host 'PASS: Challenge 37 精确 14/14 canonical tests（跳过 E2E）。'; return }
  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null } catch { throw "LocalStack 不可用：$LocalstackEndpoint" }
  $remoteMutationStarted = $true; Remove-Item -LiteralPath (Join-Path $workDir 'tests') -Recurse -Force
  $planPath = Join-Path $workDir 'reviewed.tfplan'; Invoke-Terraform $workDir (@('plan', "-out=$planPath", '-input=false', '-no-color') + $commonVars)
  $planJson = (& terraform "-chdir=$workDir" show -json $planPath) | ConvertFrom-Json -Depth 100; if ($LASTEXITCODE -ne 0) { throw '无法读取 saved plan JSON。' }
  $changes = @($planJson.resource_changes | Where-Object { $_.mode -eq 'managed' })
  $expected = @(
    'aws_vpc.rules', 'aws_security_group.compiled',
    'aws_vpc_security_group_ingress_rule.compiled["ingress|tcp|00022-00022|10.20.0.0_24"]',
    'aws_vpc_security_group_ingress_rule.compiled["ingress|tcp|00443-00443|10.10.0.0_16"]',
    'aws_vpc_security_group_ingress_rule.compiled["ingress|udp|00053-00053|10.10.0.0_16"]',
    'aws_vpc_security_group_egress_rule.compiled["egress|tcp|00443-00443|0.0.0.0_0"]'
  ) | Sort-Object
  $actual = @($changes | ForEach-Object { [string]$_.address } | Sort-Object)
  if (($actual -join ',') -ne ($expected -join ',')) { throw "saved plan graph 不精确：$($actual -join ', ')" }
  if (@($changes | Where-Object { (@($_.change.actions) -join ',') -ne 'create' }).Count -ne 0) { throw '首次 saved plan 必须全为 create。' }
  foreach ($change in @($changes | Where-Object { $_.type -like 'aws_vpc_security_group_*_rule' })) {
    if ([string]::IsNullOrWhiteSpace([string]$change.change.after.cidr_ipv4) -or $change.change.after.tags.RunId -ne $runId -or [string]::IsNullOrWhiteSpace([string]$change.change.after.tags.RuleId)) { throw "$($change.address) 的 CIDR/RuleId/RunId plan 合同不完整。" }
  }
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $planPath)
  $contract = (& terraform "-chdir=$workDir" output -json security_contract) | ConvertFrom-Json -Depth 50
  if ($contract.account_id -ne '000000000000' -or [string]::IsNullOrWhiteSpace($contract.vpc_id) -or [string]::IsNullOrWhiteSpace($contract.security_group_id) -or @($contract.rules.PSObject.Properties).Count -ne 4) { throw 'data source/security contract 输出不完整。' }
  $vpcs = Invoke-AwsJson @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$runId"); $groups = Invoke-AwsJson @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId")
  $rules = Invoke-AwsJson @('ec2', 'describe-security-group-rules', '--filters', "Name=tag:RunId,Values=$runId")
  if (@($vpcs.Vpcs).Count -ne 1 -or @($groups.SecurityGroups).Count -ne 1 -or @($rules.SecurityGroupRules).Count -ne 4) { throw "远端计数错误：VPC=$(@($vpcs.Vpcs).Count), SG=$(@($groups.SecurityGroups).Count), rules=$(@($rules.SecurityGroupRules).Count)" }
  Assert-Tag @($vpcs.Vpcs[0].Tags) 'RunId' $runId 'VPC'; Assert-Tag @($groups.SecurityGroups[0].Tags) 'RunId' $runId 'SG'
  if ($contract.vpc_id -ne $vpcs.Vpcs[0].VpcId -or $contract.security_group_id -ne $groups.SecurityGroups[0].GroupId) { throw 'data source IDs 与真实资源不一致。' }
  $expectedById = @{}
  foreach ($property in $contract.rules.PSObject.Properties) { $expectedById[$property.Value.rule_id] = $property.Value }
  foreach ($rule in @($rules.SecurityGroupRules)) {
    Assert-Tag @($rule.Tags) 'RunId' $runId 'SG rule'; $ruleIdTag = @($rule.Tags | Where-Object { $_.Key -eq 'RuleId' })
    if ($ruleIdTag.Count -ne 1 -or -not $expectedById.ContainsKey($ruleIdTag[0].Value)) { throw '远端 rule 缺少唯一已知 RuleId。' }
    $expectedRule = $expectedById[$ruleIdTag[0].Value]; $direction = if ($rule.IsEgress) { 'egress' } else { 'ingress' }
    if ($direction -ne $expectedRule.direction -or [string]$rule.IpProtocol -ne [string]$expectedRule.protocol -or [int]$rule.FromPort -ne [int]$expectedRule.from_port -or [int]$rule.ToPort -ne [int]$expectedRule.to_port -or $rule.CidrIpv4 -ne $expectedRule.cidr -or $rule.Description -ne $expectedRule.description) { throw "远端规则 $($ruleIdTag[0].Value) 语义不匹配。" }
  }
  $reorder = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color', '-var=rules_csv_path=../fixtures/rules-reordered.csv') + $commonVars) @(0, 2); if ($reorder -ne 0) { throw 'CSV 重排必须为零变更。' }
  $adminRule = @($rules.SecurityGroupRules | Where-Object { @($_.Tags | Where-Object { $_.Key -eq 'RuleId' -and $_.Value -eq 'admin-ssh' }).Count -eq 1 })
  if ($adminRule.Count -ne 1 -or $adminRule[0].IsEgress) { throw '无法唯一选择 admin-ssh ingress rule。' }
  [void](Invoke-AwsJson @('ec2', 'revoke-security-group-ingress', '--group-id', $contract.security_group_id, '--security-group-rule-ids', $adminRule[0].SecurityGroupRuleId))
  $driftPlan = Join-Path $workDir 'drift.tfplan'; $drift = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', "-out=$driftPlan", '-input=false', '-no-color') + $commonVars) @(0, 2); if ($drift -ne 2) { throw '撤销远端规则必须产生 exit 2。' }
  $driftJson = (& terraform "-chdir=$workDir" show -json $driftPlan) | ConvertFrom-Json -Depth 100; if ($LASTEXITCODE -ne 0) { throw '无法读取 drift plan JSON。' }
  $driftChanges = @($driftJson.resource_changes | Where-Object { $_.mode -eq 'managed' -and (@($_.change.actions) -join ',') -ne 'no-op' })
  $adminAddress = 'aws_vpc_security_group_ingress_rule.compiled["ingress|tcp|00022-00022|10.20.0.0_24"]'
  if ($driftChanges.Count -ne 1 -or $driftChanges[0].address -ne $adminAddress -or (@($driftChanges[0].change.actions) -join ',') -ne 'create') { throw 'drift plan 必须只重建 admin-ssh rule，禁止 delete/replace 或旁路变化。' }
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $driftPlan)
  $restoredRules = Invoke-AwsJson @('ec2', 'describe-security-group-rules', '--filters', "Name=tag:RunId,Values=$runId"); if (@($restoredRules.SecurityGroupRules).Count -ne 4) { throw '规则漂移恢复后远端计数不是4。' }
  $clean = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $commonVars) @(0, 2); if ($clean -ne 0) { throw '漂移恢复后必须是 clean plan。' }
  Invoke-Terraform $workDir (@('destroy', '-auto-approve', '-input=false', '-no-color') + $commonVars)
  $remainingVpcs = Invoke-AwsJson @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$runId"); $remainingGroups = Invoke-AwsJson @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId"); $remainingRules = Invoke-AwsJson @('ec2', 'describe-security-group-rules', '--filters', "Name=tag:RunId,Values=$runId")
  if (@($remainingVpcs.Vpcs).Count -ne 0 -or @($remainingGroups.SecurityGroups).Count -ne 0 -or @($remainingRules.SecurityGroupRules).Count -ne 0) { throw 'destroy 后仍有本 run 网络资源。' }
  Write-Host 'PASS: Challenge 37 精确 14/14 tests；LocalStack 1 VPC + 1 SG + 4 standalone rules，plan JSON、data/远端回读、reorder、单规则 drift、clean/destroy 与零残留通过。'
}
finally {
  $cleanupFailure = $null
  if ($remoteMutationStarted -and (Test-Path $workDir) -and (Test-Path (Join-Path $workDir 'terraform.tfstate'))) { try { & terraform "-chdir=$workDir" destroy -auto-approve -input=false -no-color @commonVars 2>$null | Out-Null } catch { } }
  if ($remoteMutationStarted) {
    try {
      $ruleJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-security-group-rules --filters "Name=tag:RunId,Values=$runId" --output json 2>&1); if ($LASTEXITCODE -ne 0) { throw ($ruleJson -join "`n") }
      $taggedRules = @(($ruleJson -join "`n" | ConvertFrom-Json -Depth 30).SecurityGroupRules)
      foreach ($rule in $taggedRules) {
        $operation = if ($rule.IsEgress) { 'revoke-security-group-egress' } else { 'revoke-security-group-ingress' }
        & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 $operation --group-id $rule.GroupId --security-group-rule-ids $rule.SecurityGroupRuleId 2>$null | Out-Null
      }
      $groupJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-security-groups --filters "Name=tag:RunId,Values=$runId" --output json 2>&1); if ($LASTEXITCODE -ne 0) { throw ($groupJson -join "`n") }
      foreach ($group in @(($groupJson -join "`n" | ConvertFrom-Json -Depth 30).SecurityGroups)) { & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-security-group --group-id $group.GroupId 2>$null | Out-Null }
      $vpcJson = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-vpcs --filters "Name=tag:RunId,Values=$runId" --output json 2>&1); if ($LASTEXITCODE -ne 0) { throw ($vpcJson -join "`n") }
      foreach ($vpc in @(($vpcJson -join "`n" | ConvertFrom-Json -Depth 30).Vpcs)) { & aws --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $vpc.VpcId 2>$null | Out-Null }
      $verifyVpcs = Invoke-AwsJson @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$runId"); $verifyGroups = Invoke-AwsJson @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId"); $verifyRules = Invoke-AwsJson @('ec2', 'describe-security-group-rules', '--filters', "Name=tag:RunId,Values=$runId")
      if (@($verifyVpcs.Vpcs).Count -ne 0 -or @($verifyGroups.SecurityGroups).Count -ne 0 -or @($verifyRules.SecurityGroupRules).Count -ne 0) { throw 'finally 清理后本 run 网络资源不为0。' }
    }
    catch { $cleanupFailure = $_.Exception.Message }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess; $env:AWS_SECRET_ACCESS_KEY = $oldSecret; $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
  if ($null -ne $cleanupFailure) { throw "Challenge 37 finally 清理失败：$cleanupFailure" }
}
