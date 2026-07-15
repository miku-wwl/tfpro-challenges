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
  if (-not $uri.IsAbsoluteUri -or $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or $uri.UserInfo -ne '' -or
      $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535) { throw "Unsafe LocalStack endpoint: $Value" }
}
function Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $lines = @(& $File @Arguments 2>&1); $code = $LASTEXITCODE; $ErrorActionPreference = $old
  $rendered = $lines -join "`n"; if (-not $Quiet -and $lines.Count) { $lines | Out-Host }; if ($code -notin $Allowed) { throw "$File failed ($code): $($Arguments -join ' ')`n$rendered" }
  [pscustomobject]@{ Code = $code; Text = $rendered }
}
function Tf([string]$Directory, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) { Native 'terraform' (@("-chdir=$Directory") + $Arguments) $Allowed -Quiet:$Quiet }
function Aws([string]$Region, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) { Native 'aws.exe' (@('--endpoint-url', $LocalstackEndpoint, '--region', $Region) + $Arguments) $Allowed -Quiet:$Quiet }
function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force $Destination | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if ($item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') -or $item.Extension -in @('.tfplan', '.tfstate')) { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
  }
}
function Plan-Json([string]$Directory, [string]$Plan) { (Tf $Directory @('show', '-json', $Plan) -Quiet).Text | ConvertFrom-Json }
function Action-Map($Json) { $map = @{}; foreach ($change in @($Json.resource_changes)) { $action = @($change.change.actions) -join ','; if ($action -notin @('no-op', 'read')) { $map[$change.address] = $action } }; $map }
function Assert-Map($Actual, [hashtable]$Expected, [string]$Label) {
  if ($Actual.Count -ne $Expected.Count) { throw "$Label action count mismatch: $($Actual.Keys -join ', ')" }
  foreach ($key in $Expected.Keys) { if (-not $Actual.ContainsKey($key) -or $Actual[$key] -ne $Expected[$key]) { throw "$Label action mismatch at ${key}: $($Actual[$key])" } }
}
function Tag-Map($Tags) { $map = @{}; foreach ($tag in @($Tags)) { $map[$tag.Key] = $tag.Value }; $map }

Assert-Endpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if (-not $files.Count -or @($files | Where-Object Extension -ne '.tf').Count) { throw 'Candidate must contain HCL only.' }
$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($text -match '(?i)\b(terraform_data|mock_provider|override_data|override_resource|ignore_changes|shared_credentials|assume_role)\b|terraform\s+state\s+mv|AKIA[0-9A-Z]{16}') { throw 'Forbidden workaround, state command, mock, or credential mechanism found.' }
$types = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($types -join ',') -ne 'aws_iam_instance_profile,aws_iam_role,aws_launch_template,aws_security_group') { throw "Unexpected managed AWS types: $($types -join ',')" }
if ($text -match 'resource\s+"aws_(?:vpc|subnet)"') { throw 'Network must remain external.' }
if ([regex]::Matches($text, '(?m)^\s*moved\s*\{').Count -ne 6) { throw 'Exactly six moved blocks are required.' }
foreach ($token in @('provider "aws"', 'alias                       = "dr"', 'providers = { aws = aws.dr }', 'module "identity"', 'module "primary"', 'module "dr"', 'data "aws_subnet" "target"', 'data "aws_ami" "release"')) {
  if ($text -notmatch [regex]::Escape($token)) { throw "Missing provider/module contract token: $token" }
}
foreach ($module in @('identity', 'regional')) {
  $moduleText = (Get-ChildItem -LiteralPath (Join-Path $candidatePath "modules\$module") -Filter '*.tf' -File | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
  if ($moduleText -match '(?m)^\s*provider\s+"') { throw "$module module must not configure a provider." }
}
if ($text -notmatch 'access_key\s*=\s*"test"' -or $text -notmatch 'secret_key\s*=\s*"test"' -or $text -notmatch 'skip_credentials_validation\s*=\s*true' -or
    $text -notmatch 'skip_metadata_api_check\s*=\s*true' -or $text -notmatch 'skip_requesting_account_id\s*=\s*true') { throw 'Safe LocalStack provider contract missing.' }
$versionText = (Native 'terraform' @('version', '-json') -Quiet).Text; $version = $versionText.Substring($versionText.IndexOf('{')) | ConvertFrom-Json
if ($version.terraform_version -ne '1.6.6') { throw "Terraform 1.6.6 required, found $($version.terraform_version)." }

$runId = 'c53' + ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c53-$runId"; $unit = Join-Path $temp 'unit'; $legacy = Join-Path $temp 'legacy'; $migration = Join-Path $temp 'migration'
$eastVpc = $null; $eastSubnet = $null; $drVpc = $null; $drSubnet = $null; $activeRoot = $null; $failure = $null
$oldAccess = $env:AWS_ACCESS_KEY_ID; $oldSecret = $env:AWS_SECRET_ACCESS_KEY; $oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'
try {
  try { Invoke-WebRequest -UseBasicParsing "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null } catch { throw 'LocalStack is unavailable.' }
  $eastVpc = ((Aws 'us-east-1' @('ec2', 'create-vpc', '--cidr-block', '10.153.0.0/24', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text).Trim()
  $eastSubnet = ((Aws 'us-east-1' @('ec2', 'create-subnet', '--vpc-id', $eastVpc, '--cidr-block', '10.153.0.0/28', '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text).Trim()
  $drVpc = ((Aws 'us-west-2' @('ec2', 'create-vpc', '--cidr-block', '10.253.0.0/24', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text).Trim()
  $drSubnet = ((Aws 'us-west-2' @('ec2', 'create-subnet', '--vpc-id', $drVpc, '--cidr-block', '10.253.0.0/28', '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text).Trim()
  $common = @('-input=false', '-no-color', "-var=run_id=$runId", "-var=primary_subnet_id=$eastSubnet", "-var=dr_subnet_id=$drSubnet")

  Copy-Clean $candidatePath $unit; Copy-Item (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $unit 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force (Join-Path $unit 'tests') | Out-Null; Copy-Item (Join-Path $PSScriptRoot 'canonical.tftest.hcl') (Join-Path $unit 'tests\canonical.tftest.hcl')
  Tf $unit @('fmt', '-check', '-recursive') | Out-Null; Tf $unit @('init', '-backend=false', '-input=false', '-no-color') | Out-Null; Tf $unit @('validate', '-no-color') | Out-Null
  $tests = Tf $unit @('test', '-test-directory=tests', '-no-color', "-var=run_id=$runId", "-var=primary_subnet_id=$eastSubnet", "-var=dr_subnet_id=$drSubnet")
  if ([regex]::Matches($tests.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 7 -or $tests.Text -notmatch '(?m)^Success!\s+7 passed,\s+0 failed\.\s*$') { throw 'Expected exact 7/7 canonical tests.' }
  if ($UnitOnly) { Write-Host 'PASS: Challenge 53 exact 7/7 Terraform 1.6.6 tests.'; return }

  Copy-Clean (Join-Path $PSScriptRoot '..\fixtures\legacy') $legacy; Tf $legacy @('init', '-backend=false', '-input=false', '-no-color') | Out-Null; Tf $legacy @('validate', '-no-color') | Out-Null
  $legacyCommon = @('-input=false', '-no-color', "-var=localstack_endpoint=$LocalstackEndpoint", "-var=run_id=$runId", "-var=primary_subnet_id=$eastSubnet", "-var=dr_subnet_id=$drSubnet")
  $legacyPlan = Join-Path $legacy 'legacy.tfplan'; Tf $legacy (@('plan', "-out=$legacyPlan") + $legacyCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $legacy $legacyPlan)) @{
    'aws_iam_role.legacy' = 'create'; 'aws_iam_instance_profile.legacy' = 'create'; 'aws_security_group.primary' = 'create';
    'aws_launch_template.primary' = 'create'; 'aws_security_group.dr' = 'create'; 'aws_launch_template.dr' = 'create'
  } 'legacy'
  Tf $legacy @('apply', '-input=false', '-no-color', $legacyPlan) | Out-Null; $activeRoot = $legacy

  Copy-Clean $candidatePath $migration; Copy-Item (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $migration 'fixtures') -Recurse -Force
  Tf $migration @('init', '-backend=false', '-input=false', '-no-color') | Out-Null; Copy-Item (Join-Path $legacy 'terraform.tfstate') (Join-Path $migration 'terraform.tfstate') -Force; $activeRoot = $migration
  $movedPlan = Join-Path $migration 'moved.tfplan'; Tf $migration (@('plan', "-out=$movedPlan") + $common) | Out-Null; $movedJson = Plan-Json $migration $movedPlan
  Assert-Map (Action-Map $movedJson) @{} 'migration'
  $previous = @{}; foreach ($change in @($movedJson.resource_changes)) { if ($null -ne $change.previous_address) { $previous[$change.address] = $change.previous_address } }
  $expected = @{
    'module.identity.aws_iam_role.this' = 'aws_iam_role.legacy'; 'module.identity.aws_iam_instance_profile.this' = 'aws_iam_instance_profile.legacy';
    'module.primary.aws_security_group.this' = 'aws_security_group.primary'; 'module.primary.aws_launch_template.this' = 'aws_launch_template.primary';
    'module.dr.aws_security_group.this' = 'aws_security_group.dr'; 'module.dr.aws_launch_template.this' = 'aws_launch_template.dr'
  }
  if ($previous.Count -ne 6) { throw "Expected six previous_address entries, found $($previous.Count)." }; foreach ($key in $expected.Keys) { if ($previous[$key] -ne $expected[$key]) { throw "Wrong previous_address at $key." } }
  Tf $migration @('apply', '-input=false', '-no-color', $movedPlan) | Out-Null
  $contract = (Tf $migration @('output', '-json', 'regional_contract') -Quiet).Text | ConvertFrom-Json
  $eastSg = (Aws 'us-east-1' @('ec2', 'describe-security-groups', '--group-ids', $contract.primary.security_group_id, '--output', 'json') -Quiet).Text | ConvertFrom-Json
  $drSg = (Aws 'us-west-2' @('ec2', 'describe-security-groups', '--group-ids', $contract.dr.security_group_id, '--output', 'json') -Quiet).Text | ConvertFrom-Json
  if ($eastSg.SecurityGroups[0].VpcId -ne $eastVpc -or $drSg.SecurityGroups[0].VpcId -ne $drVpc -or (Tag-Map $drSg.SecurityGroups[0].Tags).RegionKey -ne 'dr') { throw 'Real dual-region SG routing mismatch.' }
  $eastProfile = ((Aws 'us-east-1' @('ec2', 'describe-launch-template-versions', '--launch-template-id', $contract.primary.launch_template_id, '--versions', '$Default', '--query', 'LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile.Name', '--output', 'text') -Quiet).Text).Trim()
  $drProfile = ((Aws 'us-west-2' @('ec2', 'describe-launch-template-versions', '--launch-template-id', $contract.dr.launch_template_id, '--versions', '$Default', '--query', 'LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile.Name', '--output', 'text') -Quiet).Text).Trim()
  if ($eastProfile -ne $contract.profile_name -or $drProfile -ne $contract.profile_name) { throw 'Shared profile was not routed to both launch templates.' }
  $reorder = Tf $migration (@('plan', '-detailed-exitcode', '-var=catalog_path=fixtures/regions-reordered.json') + $common) @(0, 2) -Quiet; if ($reorder.Code -ne 0) { throw 'Region array reorder changed graph.' }

  Aws 'us-west-2' @('ec2', 'create-tags', '--resources', $contract.dr.security_group_id, '--tags', 'Key=Name,Value=tampered') | Out-Null
  $driftPlan = Join-Path $migration 'drift.tfplan'; $drift = Tf $migration (@('plan', '-detailed-exitcode', "-out=$driftPlan") + $common) @(0, 2) -Quiet; if ($drift.Code -ne 2) { throw 'DR SG drift was not detected.' }
  Assert-Map (Action-Map (Plan-Json $migration $driftPlan)) @{ 'module.dr.aws_security_group.this' = 'update' } 'DR drift'
  Tf $migration @('apply', '-input=false', '-no-color', $driftPlan) | Out-Null; $clean = Tf $migration (@('plan', '-detailed-exitcode') + $common) @(0, 2) -Quiet; if ($clean.Code -ne 0) { throw 'Final plan is not clean.' }
  Tf $migration (@('destroy', '-auto-approve') + $common) | Out-Null
  $eastGroups = (Aws 'us-east-1' @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text') -Quiet).Text
  $drGroups = (Aws 'us-west-2' @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text') -Quiet).Text
  $roles = (Aws 'us-east-1' @('iam', 'list-roles', '--query', "Roles[?contains(RoleName, '$runId')].RoleName", '--output', 'text') -Quiet).Text
  $profiles = (Aws 'us-east-1' @('iam', 'list-instance-profiles', '--query', "InstanceProfiles[?contains(InstanceProfileName, '$runId')].InstanceProfileName", '--output', 'text') -Quiet).Text
  if (-not [string]::IsNullOrWhiteSpace($eastGroups) -or -not [string]::IsNullOrWhiteSpace($drGroups) -or -not [string]::IsNullOrWhiteSpace($roles) -or -not [string]::IsNullOrWhiteSpace($profiles)) { throw 'Dual-region/IAM residue remains.' }
  Write-Host 'PASS: Challenge 53 TF1.6.6 + six-address dual-region migration + DR drift repair + zero residue.'
} catch { $failure = $_ } finally {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  if ($activeRoot -and (Test-Path (Join-Path $activeRoot 'terraform.tfstate'))) {
    if ($activeRoot -eq $legacy) { & terraform "-chdir=$legacy" destroy -auto-approve -input=false -no-color "-var=localstack_endpoint=$LocalstackEndpoint" "-var=run_id=$runId" "-var=primary_subnet_id=$eastSubnet" "-var=dr_subnet_id=$drSubnet" 2>$null | Out-Null }
    else { & terraform "-chdir=$migration" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" "-var=primary_subnet_id=$eastSubnet" "-var=dr_subnet_id=$drSubnet" 2>$null | Out-Null }
  }
  if ($eastSubnet) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $eastSubnet 2>$null | Out-Null }; if ($eastVpc) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $eastVpc 2>$null | Out-Null }
  if ($drSubnet) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-subnet --subnet-id $drSubnet 2>$null | Out-Null }; if ($drVpc) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-vpc --vpc-id $drVpc 2>$null | Out-Null }
  $env:AWS_ACCESS_KEY_ID = $oldAccess; $env:AWS_SECRET_ACCESS_KEY = $oldSecret; $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }; $ErrorActionPreference = $old
}
if ($failure) { throw $failure }
