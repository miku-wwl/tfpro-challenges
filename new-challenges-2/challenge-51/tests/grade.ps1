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
  if ($Value -notmatch '^https?://(?:localhost|127\.0\.0\.1|\[::1\]):[0-9]{1,5}$') {
    throw "Unsafe LocalStack endpoint: $Value"
  }
  try { $uri = [Uri]$Value } catch { throw "Unsafe LocalStack endpoint: $Value" }
  if (-not $uri.IsAbsoluteUri -or $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or
      $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or
      $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535) {
    throw "Unsafe LocalStack endpoint: $Value"
  }
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

function Assert-Managed-State([string]$Directory, [string]$Label) {
  $managed = @((Tf $Directory @('state', 'list') -Quiet).Text -split "`n" |
    Where-Object { $_ -match '^(?:module\.[^.]+\.)?aws_' } | Sort-Object)
  $expected = @(
    'module.workload.aws_iam_instance_profile.this',
    'module.workload.aws_iam_role.this',
    'module.workload.aws_instance.this'
  ) | Sort-Object
  if (($managed -join "`n") -ne ($expected -join "`n")) {
    throw "$Label managed state mismatch: $($managed -join ', ')"
  }
}

Assert-Endpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if (-not $files.Count -or @($files | Where-Object Extension -ne '.tf').Count) {
  throw 'Candidate must contain HCL only.'
}
$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($text -match '(?i)\b(terraform_data|mock_provider|override_data|override_resource|ignore_changes|shared_credentials|assume_role)\b|terraform\s+state\s+mv|AKIA[0-9A-Z]{16}') {
  throw 'Forbidden workaround, state command, mock, or credential mechanism found.'
}
$types = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') |
  ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($types -join ',') -ne 'aws_iam_instance_profile,aws_iam_role,aws_instance') {
  throw "Unexpected managed AWS types: $($types -join ',')"
}
if ($text -match 'resource\s+"aws_(?:vpc|subnet)"') { throw 'Network must remain external.' }
if ([regex]::Matches($text, '(?m)^\s*import\s*\{').Count -ne 3) { throw 'Exactly three import blocks are required.' }
if ([regex]::Matches($text, '(?m)^\s*moved\s*\{').Count -ne 3) { throw 'Exactly three moved blocks are required.' }
foreach ($token in @(
  'to = module.workload.aws_iam_role.this',
  'to = module.workload.aws_iam_instance_profile.this',
  'to = module.workload.aws_instance.this',
  'from = aws_iam_role.legacy',
  'from = aws_iam_instance_profile.legacy',
  'from = aws_instance.legacy',
  'data "aws_subnet" "target"',
  'data "aws_ami" "target"'
)) {
  if ($text -notmatch [regex]::Escape($token)) { throw "Missing takeover contract token: $token" }
}
$moduleText = (Get-ChildItem -LiteralPath (Join-Path $candidatePath 'modules\workload') -Filter '*.tf' -File |
  ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($moduleText -match '(?m)^\s*provider\s+"') { throw 'The child module must not configure a provider.' }
if ($text -notmatch 'access_key\s*=\s*"test"' -or $text -notmatch 'secret_key\s*=\s*"test"' -or
    $text -notmatch 'skip_credentials_validation\s*=\s*true' -or
    $text -notmatch 'skip_metadata_api_check\s*=\s*true' -or
    $text -notmatch 'skip_requesting_account_id\s*=\s*true') {
  throw 'Safe LocalStack provider contract missing.'
}
$version = (Native 'terraform' @('version', '-json') -Quiet).Text | ConvertFrom-Json
if ($version.terraform_version -ne '1.6.6') { throw "Terraform 1.6.6 required, found $($version.terraform_version)." }

$runId = 'c51' + ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
$roleName = "$runId-role"
$profileName = "$runId-profile"
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c51-$runId"
$legacy = Join-Path $temp 'legacy'
$unit = Join-Path $temp 'unit'
$migration = Join-Path $temp 'migration'
$importRoot = Join-Path $temp 'import'
$vpc = $null
$subnet = $null
$instanceId = $null
$failure = $null
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
$legacyCommon = @('-input=false', '-no-color', "-var=localstack_endpoint=$LocalstackEndpoint", "-var=run_id=$runId", "-var=role_name=$roleName", "-var=profile_name=$profileName")

try {
  try {
    Invoke-WebRequest -UseBasicParsing "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null
  } catch { throw 'LocalStack is unavailable.' }

  $vpc = ((Aws @('ec2', 'create-vpc', '--cidr-block', '10.151.0.0/24', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text).Trim()
  $subnet = ((Aws @('ec2', 'create-subnet', '--vpc-id', $vpc, '--cidr-block', '10.151.0.0/28', '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text).Trim()
  $legacyCommon += "-var=subnet_id=$subnet"

  Copy-Clean (Join-Path $PSScriptRoot '..\fixtures\legacy') $legacy
  Tf $legacy @('fmt', '-check', '-recursive') | Out-Null
  Tf $legacy @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Tf $legacy @('validate', '-no-color') | Out-Null
  $legacyPlan = Join-Path $legacy 'legacy.tfplan'
  Tf $legacy (@('plan', "-out=$legacyPlan") + $legacyCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $legacy $legacyPlan)) @{
    'aws_iam_role.legacy'             = 'create'
    'aws_iam_instance_profile.legacy' = 'create'
    'aws_instance.legacy'             = 'create'
  } 'legacy'
  Tf $legacy @('apply', '-input=false', '-no-color', $legacyPlan) | Out-Null
  $instanceId = ((Tf $legacy @('output', '-raw', 'instance_id') -Quiet).Text).Trim()

  Copy-Clean $candidatePath $unit
  Copy-Item (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $unit 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force (Join-Path $unit 'tests') | Out-Null
  Copy-Item (Join-Path $PSScriptRoot 'canonical.tftest.hcl') (Join-Path $unit 'tests\canonical.tftest.hcl')
  Tf $unit @('fmt', '-check', '-recursive') | Out-Null
  Tf $unit @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Tf $unit @('validate', '-no-color') | Out-Null
  $tests = Tf $unit @(
    'test', '-test-directory=tests', '-no-color',
    "-var=run_id=$runId", "-var=subnet_id=$subnet", "-var=legacy_role_name=$roleName",
    "-var=legacy_profile_name=$profileName", "-var=legacy_instance_id=$instanceId"
  )
  if ([regex]::Matches($tests.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 6 -or
      $tests.Text -notmatch '(?m)^Success!\s+6 passed,\s+0 failed\.\s*$') {
    throw 'Expected exact 6/6 canonical tests.'
  }
  if ($UnitOnly) {
    Write-Host 'PASS: Challenge 51 exact 6/6 Terraform 1.6.6 tests.'
    return
  }

  Copy-Clean $candidatePath $migration
  Copy-Item (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $migration 'fixtures') -Recurse -Force
  Tf $migration @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Copy-Item -LiteralPath (Join-Path $legacy 'terraform.tfstate') -Destination (Join-Path $migration 'terraform.tfstate') -Force
  $common = @(
    '-input=false', '-no-color', "-var=run_id=$runId", "-var=subnet_id=$subnet",
    "-var=legacy_role_name=$roleName", "-var=legacy_profile_name=$profileName", "-var=legacy_instance_id=$instanceId"
  )
  $movedPlan = Join-Path $migration 'moved.tfplan'
  Tf $migration (@('plan', "-out=$movedPlan") + $common) | Out-Null
  $movedJson = Plan-Json $migration $movedPlan
  Assert-Map (Action-Map $movedJson) @{} 'moved takeover'
  $previous = @{}
  foreach ($change in @($movedJson.resource_changes)) {
    if ($null -ne $change.previous_address) { $previous[$change.address] = $change.previous_address }
  }
  $expectedPrevious = @{
    'module.workload.aws_iam_role.this'             = 'aws_iam_role.legacy'
    'module.workload.aws_iam_instance_profile.this' = 'aws_iam_instance_profile.legacy'
    'module.workload.aws_instance.this'             = 'aws_instance.legacy'
  }
  if ($previous.Count -ne 3) { throw "Expected three previous_address entries, found $($previous.Count)." }
  foreach ($key in $expectedPrevious.Keys) {
    if ($previous[$key] -ne $expectedPrevious[$key]) { throw "Wrong previous_address at $key." }
  }
  Tf $migration @('apply', '-input=false', '-no-color', $movedPlan) | Out-Null
  Assert-Managed-State $migration 'moved takeover'
  $reorder = Tf $migration (@('plan', '-detailed-exitcode', '-var=catalog_path=fixtures/takeover-reordered.json') + $common) @(0, 2) -Quiet
  if ($reorder.Code -ne 0) { throw 'Reordered takeover catalog changed the migrated graph.' }

  Copy-Clean $candidatePath $importRoot
  Copy-Item (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $importRoot 'fixtures') -Recurse -Force
  Tf $importRoot @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  $importPlan = Join-Path $importRoot 'import.tfplan'
  Tf $importRoot (@('plan', "-out=$importPlan") + $common) | Out-Null
  $importJson = Plan-Json $importRoot $importPlan
  Assert-Map (Action-Map $importJson) @{} 'declarative import'
  $imported = @($importJson.resource_changes | Where-Object { $null -ne $_.change.importing } |
    ForEach-Object { $_.address } | Sort-Object)
  $expectedImported = @(
    'module.workload.aws_iam_instance_profile.this',
    'module.workload.aws_iam_role.this',
    'module.workload.aws_instance.this'
  ) | Sort-Object
  if (($imported -join "`n") -ne ($expectedImported -join "`n")) {
    throw "Declarative import set mismatch: $($imported -join ', ')"
  }
  Tf $importRoot @('apply', '-input=false', '-no-color', $importPlan) | Out-Null
  Assert-Managed-State $importRoot 'declarative import'
  $cleanImport = Tf $importRoot (@('plan', '-detailed-exitcode') + $common) @(0, 2) -Quiet
  if ($cleanImport.Code -ne 0) { throw 'Imported configuration is not clean.' }

  Aws @('ec2', 'create-tags', '--resources', $instanceId, '--tags', 'Key=Name,Value=tampered') | Out-Null
  $driftPlan = Join-Path $importRoot 'drift.tfplan'
  $drift = Tf $importRoot (@('plan', '-detailed-exitcode', "-out=$driftPlan") + $common) @(0, 2) -Quiet
  if ($drift.Code -ne 2) { throw 'Real EC2 tag drift was not detected.' }
  Assert-Map (Action-Map (Plan-Json $importRoot $driftPlan)) @{
    'module.workload.aws_instance.this' = 'update'
  } 'drift repair'
  Tf $importRoot @('apply', '-input=false', '-no-color', $driftPlan) | Out-Null
  $clean = Tf $importRoot (@('plan', '-detailed-exitcode') + $common) @(0, 2) -Quiet
  if ($clean.Code -ne 0) { throw 'Final plan is not clean.' }
  Tf $importRoot (@('destroy', '-auto-approve') + $common) | Out-Null

  $active = (Aws @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text') -Quiet).Text
  $roles = (Aws @('iam', 'list-roles', '--query', "Roles[?contains(RoleName, '$runId')].RoleName", '--output', 'text') -Quiet).Text
  $profiles = (Aws @('iam', 'list-instance-profiles', '--query', "InstanceProfiles[?contains(InstanceProfileName, '$runId')].InstanceProfileName", '--output', 'text') -Quiet).Text
  if (-not [string]::IsNullOrWhiteSpace($active) -or -not [string]::IsNullOrWhiteSpace($roles) -or -not [string]::IsNullOrWhiteSpace($profiles)) {
    throw 'Run-scoped EC2/IAM residue remains.'
  }
  Write-Host 'PASS: Challenge 51 TF1.6.6 + moved/import saved-plan audits + real LocalStack drift + zero residue.'
} catch {
  $failure = $_
} finally {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  foreach ($root in @($importRoot, $migration, $legacy)) {
    if (Test-Path (Join-Path $root 'terraform.tfstate')) {
      if ($root -eq $legacy) {
        & terraform "-chdir=$root" destroy -auto-approve @legacyCommon 2>$null | Out-Null
      } elseif ($instanceId -and $subnet) {
        & terraform "-chdir=$root" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" "-var=subnet_id=$subnet" "-var=legacy_role_name=$roleName" "-var=legacy_profile_name=$profileName" "-var=legacy_instance_id=$instanceId" 2>$null | Out-Null
      }
    }
  }
  if ($subnet) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $subnet 2>$null | Out-Null }
  if ($vpc) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $vpc 2>$null | Out-Null }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
  $ErrorActionPreference = $old
}
if ($failure) { throw $failure }
