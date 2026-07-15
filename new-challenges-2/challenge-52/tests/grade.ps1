[CmdletBinding()]
param(
  [string]$Candidate = '',
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)

if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Endpoint([string]$Value) {
  if ($Value -notmatch '^https?://(?:localhost|127\.0\.0\.1|\[::1\]):[0-9]{1,5}$') { throw "Unsafe LocalStack endpoint: $Value" }
  try { $uri = [Uri]$Value } catch { throw "Unsafe LocalStack endpoint: $Value" }
  if (-not $uri.IsAbsoluteUri -or $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or
      $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or
      $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535) { throw "Unsafe LocalStack endpoint: $Value" }
}

function Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $lines = @(& $File @Arguments 2>&1)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  $rendered = $lines -join "`n"
  if (-not $Quiet -and $lines.Count) { $lines | Out-Host }
  if ($code -notin $Allowed) { throw "$File failed ($code): $($Arguments -join ' ')`n$rendered" }
  [pscustomobject]@{ Code = $code; Text = $rendered }
}

function Tf([string]$Directory, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  Native 'terraform' (@("-chdir=$Directory") + $Arguments) $Allowed -Quiet:$Quiet
}

function Aws([string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  Native 'aws.exe' (@('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1') + $Arguments) $Allowed -Quiet:$Quiet
}

function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force $Destination | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if ($item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') -or
        $item.Extension -in @('.tfplan', '.tfstate')) { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
  }
}

function Plan-Json([string]$Directory, [string]$Plan) {
  (Tf $Directory @('show', '-json', $Plan) -Quiet).Text | ConvertFrom-Json
}

function Action-Map($Json) {
  $map = @{}
  foreach ($change in @($Json.resource_changes)) {
    $action = @($change.change.actions) -join ','
    if ($action -notin @('no-op', 'read')) { $map[$change.address] = $action }
  }
  $map
}

function Assert-Map($Actual, [hashtable]$Expected, [string]$Label) {
  if ($Actual.Count -ne $Expected.Count) { throw "$Label action count mismatch: $($Actual.Keys -join ', ')" }
  foreach ($key in $Expected.Keys) {
    if (-not $Actual.ContainsKey($key) -or $Actual[$key] -ne $Expected[$key]) {
      throw "$Label action mismatch at ${key}: $($Actual[$key])"
    }
  }
}

Assert-Endpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if (-not $files.Count -or @($files | Where-Object Extension -ne '.tf').Count) { throw 'Candidate must contain HCL only.' }
$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($text -match '(?i)\b(terraform_data|mock_provider|override_data|override_resource|ignore_changes|shared_credentials|assume_role)\b|terraform\s+state\s+mv|AKIA[0-9A-Z]{16}') {
  throw 'Forbidden workaround, state command, mock, or credential mechanism found.'
}
$types = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($types -join ',') -ne 'aws_security_group,aws_vpc_security_group_ingress_rule') { throw "Unexpected managed AWS types: $($types -join ',')" }
if ($text -match 'resource\s+"aws_(?:vpc|subnet)"') { throw 'VPC and subnet must remain external.' }
if ($text -match '(?m)^\s*(?:ingress|egress)\s*\{') { throw 'Inline SG rules are forbidden.' }
if ([regex]::Matches($text, '(?m)^\s*moved\s*\{').Count -ne 4) { throw 'Exactly four moved blocks are required.' }
foreach ($token in @(
  'from = aws_security_group.legacy',
  'to   = module.ingress.aws_security_group.this',
  'from = aws_vpc_security_group_ingress_rule.legacy[0]',
  'to   = module.ingress.aws_vpc_security_group_ingress_rule.this["admin"]',
  'from = aws_vpc_security_group_ingress_rule.legacy[1]',
  'to   = module.ingress.aws_vpc_security_group_ingress_rule.this["api"]',
  'from = aws_vpc_security_group_ingress_rule.legacy[2]',
  'to   = module.ingress.aws_vpc_security_group_ingress_rule.this["metrics"]',
  'for_each = var.rules'
)) {
  if ($text -notmatch [regex]::Escape($token)) { throw "Missing migration contract token: $token" }
}
$moduleText = (Get-ChildItem -LiteralPath (Join-Path $candidatePath 'modules\ingress') -Filter '*.tf' -File |
  ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($moduleText -match '(?m)^\s*provider\s+"') { throw 'Child module must not configure a provider.' }
if ($text -notmatch 'access_key\s*=\s*"test"' -or $text -notmatch 'secret_key\s*=\s*"test"' -or
    $text -notmatch 'skip_credentials_validation\s*=\s*true' -or
    $text -notmatch 'skip_metadata_api_check\s*=\s*true' -or
    $text -notmatch 'skip_requesting_account_id\s*=\s*true') { throw 'Safe LocalStack provider contract missing.' }
$versionText = (Native 'terraform' @('version', '-json') -Quiet).Text
$versionJson = $versionText.Substring($versionText.IndexOf('{')) | ConvertFrom-Json
if ($versionJson.terraform_version -ne '1.6.6') { throw "Terraform 1.6.6 required, found $($versionJson.terraform_version)." }

$runId = 'c52' + ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c52-$runId"
$unit = Join-Path $temp 'unit'
$legacy = Join-Path $temp 'legacy'
$migration = Join-Path $temp 'migration'
$vpc = $null
$activeRoot = $null
$failure = $null
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'

try {
  try { Invoke-WebRequest -UseBasicParsing "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null } catch { throw 'LocalStack is unavailable.' }
  $vpc = ((Aws @('ec2', 'create-vpc', '--cidr-block', '10.152.0.0/24', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text).Trim()
  $common = @('-input=false', '-no-color', "-var=run_id=$runId", "-var=vpc_id=$vpc")

  Copy-Clean $candidatePath $unit
  Copy-Item (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $unit 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force (Join-Path $unit 'tests') | Out-Null
  Copy-Item (Join-Path $PSScriptRoot 'canonical.tftest.hcl') (Join-Path $unit 'tests\canonical.tftest.hcl')
  Tf $unit @('fmt', '-check', '-recursive') | Out-Null
  Tf $unit @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Tf $unit @('validate', '-no-color') | Out-Null
  $tests = Tf $unit @('test', '-test-directory=tests', '-no-color', "-var=run_id=$runId", "-var=vpc_id=$vpc")
  if ([regex]::Matches($tests.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 7 -or
      $tests.Text -notmatch '(?m)^Success!\s+7 passed,\s+0 failed\.\s*$') { throw 'Expected exact 7/7 canonical tests.' }
  if ($UnitOnly) { Write-Host 'PASS: Challenge 52 exact 7/7 Terraform 1.6.6 tests.'; return }

  Copy-Clean (Join-Path $PSScriptRoot '..\fixtures\legacy') $legacy
  Copy-Item (Join-Path $PSScriptRoot '..\fixtures\rules.csv') (Join-Path $legacy 'rules.csv')
  Tf $legacy @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Tf $legacy @('validate', '-no-color') | Out-Null
  $legacyCommon = @('-input=false', '-no-color', "-var=localstack_endpoint=$LocalstackEndpoint", "-var=run_id=$runId", "-var=vpc_id=$vpc", '-var=catalog_path=rules.csv')
  $legacyPlan = Join-Path $legacy 'legacy.tfplan'
  Tf $legacy (@('plan', "-out=$legacyPlan") + $legacyCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $legacy $legacyPlan)) @{
    'aws_security_group.legacy'                       = 'create'
    'aws_vpc_security_group_ingress_rule.legacy[0]' = 'create'
    'aws_vpc_security_group_ingress_rule.legacy[1]' = 'create'
    'aws_vpc_security_group_ingress_rule.legacy[2]' = 'create'
  } 'legacy'
  Tf $legacy @('apply', '-input=false', '-no-color', $legacyPlan) | Out-Null
  $activeRoot = $legacy

  Copy-Clean $candidatePath $migration
  Copy-Item (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $migration 'fixtures') -Recurse -Force
  Tf $migration @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Copy-Item (Join-Path $legacy 'terraform.tfstate') (Join-Path $migration 'terraform.tfstate') -Force
  $activeRoot = $migration
  $movedPlan = Join-Path $migration 'moved.tfplan'
  Tf $migration (@('plan', "-out=$movedPlan") + $common) | Out-Null
  $movedJson = Plan-Json $migration $movedPlan
  Assert-Map (Action-Map $movedJson) @{} 'migration'
  $previous = @{}
  foreach ($change in @($movedJson.resource_changes)) {
    if ($null -ne $change.previous_address) { $previous[$change.address] = $change.previous_address }
  }
  $expectedPrevious = @{
    'module.ingress.aws_security_group.this'                                      = 'aws_security_group.legacy'
    'module.ingress.aws_vpc_security_group_ingress_rule.this["admin"]'           = 'aws_vpc_security_group_ingress_rule.legacy[0]'
    'module.ingress.aws_vpc_security_group_ingress_rule.this["api"]'             = 'aws_vpc_security_group_ingress_rule.legacy[1]'
    'module.ingress.aws_vpc_security_group_ingress_rule.this["metrics"]'         = 'aws_vpc_security_group_ingress_rule.legacy[2]'
  }
  if ($previous.Count -ne 4) { throw "Expected four previous_address entries, found $($previous.Count)." }
  foreach ($key in $expectedPrevious.Keys) {
    if ($previous[$key] -ne $expectedPrevious[$key]) { throw "Wrong previous_address at $key." }
  }
  Tf $migration @('apply', '-input=false', '-no-color', $movedPlan) | Out-Null

  $managed = @((Tf $migration @('state', 'list') -Quiet).Text -split "`n" | Where-Object { $_ -match '^(?:module\.[^.]+\.)?aws_' } | Sort-Object)
  if ($managed.Count -ne 4 -or $managed -notcontains 'module.ingress.aws_security_group.this') { throw "Migrated state contract mismatch: $($managed -join ', ')" }
  $contract = (Tf $migration @('output', '-json', 'rule_contract') -Quiet).Text | ConvertFrom-Json
  $remoteRules = (Aws @('ec2', 'describe-security-group-rules', '--filters', "Name=group-id,Values=$($contract.security_group_id)", '--query', 'SecurityGroupRules[?IsEgress==`false`]', '--output', 'json') -Quiet).Text | ConvertFrom-Json
  if (@($remoteRules).Count -ne 3) { throw "Expected three real ingress rules, found $(@($remoteRules).Count)." }
  foreach ($key in @('admin', 'api', 'metrics')) {
    $rule = @($remoteRules | Where-Object { @($_.Tags | Where-Object Key -eq 'RuleKey').Value -contains $key })
    if ($rule.Count -ne 1 -or $rule[0].SecurityGroupRuleId -ne $contract.rule_ids.$key) { throw "Remote rule contract mismatch for $key." }
  }
  $reorder = Tf $migration (@('plan', '-detailed-exitcode', '-var=catalog_path=fixtures/rules-reordered.csv') + $common) @(0, 2) -Quiet
  if ($reorder.Code -ne 0) { throw 'CSV row reorder changed the graph.' }

  Aws @('ec2', 'revoke-security-group-ingress', '--group-id', $contract.security_group_id, '--security-group-rule-ids', $contract.rule_ids.admin) | Out-Null
  $driftPlan = Join-Path $migration 'drift.tfplan'
  $drift = Tf $migration (@('plan', '-detailed-exitcode', "-out=$driftPlan") + $common) @(0, 2) -Quiet
  if ($drift.Code -ne 2) { throw 'Deleted ingress rule drift was not detected.' }
  Assert-Map (Action-Map (Plan-Json $migration $driftPlan)) @{
    'module.ingress.aws_vpc_security_group_ingress_rule.this["admin"]' = 'create'
  } 'rule drift'
  Tf $migration @('apply', '-input=false', '-no-color', $driftPlan) | Out-Null
  $clean = Tf $migration (@('plan', '-detailed-exitcode') + $common) @(0, 2) -Quiet
  if ($clean.Code -ne 0) { throw 'Final plan is not clean.' }
  Tf $migration (@('destroy', '-auto-approve') + $common) | Out-Null
  $groups = (Aws @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text') -Quiet).Text
  if (-not [string]::IsNullOrWhiteSpace($groups)) { throw 'Run-scoped security group residue remains.' }
  Write-Host 'PASS: Challenge 52 TF1.6.6 + 4-address zero-action migration + keyed drift repair + zero residue.'
} catch {
  $failure = $_
} finally {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  if ($activeRoot -and (Test-Path (Join-Path $activeRoot 'terraform.tfstate'))) {
    if ($activeRoot -eq $legacy) {
      & terraform "-chdir=$legacy" destroy -auto-approve -input=false -no-color "-var=localstack_endpoint=$LocalstackEndpoint" "-var=run_id=$runId" "-var=vpc_id=$vpc" '-var=catalog_path=rules.csv' 2>$null | Out-Null
    } else {
      & terraform "-chdir=$migration" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" "-var=vpc_id=$vpc" 2>$null | Out-Null
    }
  }
  if ($vpc) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $vpc 2>$null | Out-Null }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
  $ErrorActionPreference = $old
}
if ($failure) { throw $failure }
