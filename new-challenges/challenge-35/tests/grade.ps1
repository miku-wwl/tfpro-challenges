[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot '..\starter'),
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Endpoint([string]$Value) {
  if ($Value -notmatch '^https?://(?:localhost|127\.0\.0\.1|\[::1\]):[0-9]{1,5}$') { throw "Unsafe endpoint: $Value" }
  try { $uri = [Uri]$Value } catch { throw "Invalid endpoint: $Value" }
  if (-not $uri.IsAbsoluteUri -or $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535) { throw "Unsafe endpoint: $Value" }
}
function Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $lines = @(& $File @Arguments 2>&1)
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  $text = $lines -join "`n"
  if (-not $Quiet -and $lines.Count) { $lines | Out-Host }
  if ($code -notin $Allowed) { throw "$File failed ($code): $($Arguments -join ' ')`n$text" }
  [pscustomobject]@{ Code = $code; Text = $text }
}
function Tf([string]$Dir, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) { Native 'terraform' (@("-chdir=$Dir") + $Arguments) $Allowed -Quiet:$Quiet }
function Aws([string]$Region, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) { Native 'aws.exe' (@('--endpoint-url', $LocalstackEndpoint, '--region', $Region) + $Arguments) $Allowed -Quiet:$Quiet }
function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force $Destination | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if ($item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') -or $item.Extension -in @('.tfplan', '.tfstate')) { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
  }
}
function Exact-Tests([string]$Dir, [int]$Expected) {
  $result = Tf $Dir @('test', '-test-directory=tests', '-no-color')
  if ([regex]::Matches($result.Text, "(?m)^Success!\s+$Expected passed,\s+0 failed\.\s*$").Count -ne 1 -or [regex]::Matches($result.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne $Expected) { throw "Expected exactly $Expected passing test runs." }
}
function Backend-Args([string]$Bucket, [string]$Key) {
  @('init', '-input=false', '-no-color', "-backend-config=bucket=$Bucket", "-backend-config=key=$Key", '-backend-config=region=us-east-1', "-backend-config=endpoint=$LocalstackEndpoint", '-backend-config=access_key=test', '-backend-config=secret_key=test', '-backend-config=force_path_style=true', '-backend-config=skip_credentials_validation=true', '-backend-config=skip_metadata_api_check=true', '-backend-config=skip_requesting_account_id=true')
}
function Plan-Json([string]$Dir, [string]$Plan) { (Tf $Dir @('show', '-json', $Plan) -Quiet).Text | ConvertFrom-Json }

Assert-Endpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if ($files.Count -eq 0 -or @($files | Where-Object Extension -ne '.tf').Count) { throw 'Candidate must contain Terraform HCL only.' }
$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($text -match '(?i)\b(mock_provider|override_data|override_resource|terraform_data|ignore_changes|desired_capacity|min_size|max_size|replica|shared_credentials|assume_role)\b|AKIA[0-9A-Z]{16}') { throw 'Forbidden workaround, capacity emulation, credential, or test mechanism found.' }
if ([regex]::Matches($text, 'backend\s+"s3"\s*\{\s*\}').Count -ne 2) { throw 'Both roots require empty partial S3 backends.' }
if ([regex]::Matches($text, 'data\s+"terraform_remote_state"').Count -ne 1 -or $text -notmatch 'backend\s*=\s*"s3"') { throw 'Fleet must consume exactly one S3 remote state.' }
$resources = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$data = @([regex]::Matches($text, 'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$allowedResources = @('aws_iam_instance_profile', 'aws_iam_role', 'aws_instance', 'aws_launch_template', 'aws_security_group')
$allowedData = @('aws_ami', 'aws_iam_policy_document', 'aws_subnet')
if (@($resources | Where-Object { $_ -notin $allowedResources }).Count -or @($data | Where-Object { $_ -notin $allowedData }).Count) { throw "Out-of-syllabus AWS type: resources=$($resources -join ',') data=$($data -join ',')" }
if ($text -match 'resource\s+"aws_(?:vpc|subnet)"') { throw 'Candidate must not manage the external network.' }
if ($text -notmatch 'data\s+"aws_subnet"\s+"dr"[\s\S]*?provider\s*=\s*aws\.dr' -or $text -notmatch 'resource\s+"aws_security_group"\s+"dr"[\s\S]*?provider\s*=\s*aws\.dr' -or $text -notmatch 'data\s+"aws_ami"\s+"dr"[\s\S]*?provider\s*=\s*aws\.dr') { throw 'DR data/resource routing is incomplete.' }
if ($text -notmatch 'module\s+"primary"[\s\S]*?providers\s*=\s*\{\s*aws\s*=\s*aws\s*\}' -or $text -notmatch 'module\s+"dr"[\s\S]*?providers\s*=\s*\{\s*aws\s*=\s*aws\.dr\s*\}') { throw 'Static module provider routing is incomplete.' }
if ([regex]::Matches($text, 'output\s+"(?:foundation_guard|upstream_guard|catalog_guard)"[\s\S]*?precondition').Count -lt 3) { throw 'Blocking contract preconditions are incomplete.' }
if ($text -notmatch 'LaunchTemplateId\s*=\s*aws_launch_template\.fleet\[each\.key\]\.id') { throw 'Instance audit tags must reference the managed launch template.' }
$child = Get-Content -Raw -LiteralPath (Join-Path $candidatePath 'fleet\modules\regional\main.tf')
if ($child -match 'provider\s+"aws"') { throw 'Child module must not configure providers.' }
if ($text -notmatch 'access_key\s*=\s*"test"' -or $text -notmatch 'secret_key\s*=\s*"test"' -or $text -notmatch 'skip_credentials_validation\s*=\s*true' -or $text -notmatch 'skip_metadata_api_check\s*=\s*true' -or $text -notmatch 'skip_requesting_account_id\s*=\s*true') { throw 'Safe LocalStack provider contract missing.' }

$version = (Native 'terraform' @('version', '-json') -Quiet).Text | ConvertFrom-Json
if ($version.terraform_version -notmatch '^1\.6\.') { throw "Terraform 1.6.x required, found $($version.terraform_version)." }
$runId = 'c35' + ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c35-$runId"
$work = Join-Path $temp 'candidate'
$stateBucket = "tfpro-c35-state-$runId"
$keys = @{ foundation = 'states/foundation.tfstate'; fleet = 'states/fleet.tfstate' }
$roots = @{}
$vpcs = @{}
$subnets = @{}
$failure = $null
$oldA = $env:AWS_ACCESS_KEY_ID; $oldS = $env:AWS_SECRET_ACCESS_KEY; $oldR = $env:AWS_DEFAULT_REGION
$oldRun = $env:TF_VAR_run_id; $oldBucket = $env:TF_VAR_state_bucket; $oldKey = $env:TF_VAR_foundation_state_key
$oldPrimarySubnet = $env:TF_VAR_primary_subnet_id; $oldDrSubnet = $env:TF_VAR_dr_subnet_id
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'
$env:TF_VAR_run_id = $runId; $env:TF_VAR_state_bucket = $stateBucket; $env:TF_VAR_foundation_state_key = $keys.foundation
try {
  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null } catch { throw 'LocalStack unavailable.' }
  Aws 'us-east-1' @('s3api', 'create-bucket', '--bucket', $stateBucket) | Out-Null
  $vpcs.primary = (Aws 'us-east-1' @('ec2', 'create-vpc', '--cidr-block', '10.135.0.0/16', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text.Trim()
  $subnets.primary = (Aws 'us-east-1' @('ec2', 'create-subnet', '--vpc-id', $vpcs.primary, '--cidr-block', '10.135.1.0/24', '--availability-zone', 'us-east-1a', '--tag-specifications', "ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text.Trim()
  $vpcs.dr = (Aws 'us-west-2' @('ec2', 'create-vpc', '--cidr-block', '10.235.0.0/16', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text.Trim()
  $subnets.dr = (Aws 'us-west-2' @('ec2', 'create-subnet', '--vpc-id', $vpcs.dr, '--cidr-block', '10.235.1.0/24', '--availability-zone', 'us-west-2a', '--tag-specifications', "ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text.Trim()
  $env:TF_VAR_primary_subnet_id = $subnets.primary; $env:TF_VAR_dr_subnet_id = $subnets.dr

  Copy-Clean $candidatePath $work
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\fixtures') -Destination (Join-Path $temp 'fixtures') -Recurse -Force
  foreach ($name in @('foundation', 'fleet')) {
    $roots[$name] = Join-Path $work $name
    New-Item -ItemType Directory -Force (Join-Path $roots[$name] 'tests') | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "$name.tftest.hcl") -Destination (Join-Path $roots[$name] "tests\$name.tftest.hcl")
    Tf $roots[$name] (Backend-Args $stateBucket $keys[$name]) | Out-Null
    Tf $roots[$name] @('fmt', '-check', '-recursive') | Out-Null
    Tf $roots[$name] @('validate', '-no-color') | Out-Null
  }

  Exact-Tests $roots.foundation 3
  $foundationPlan = Join-Path $roots.foundation 'foundation.tfplan'
  Tf $roots.foundation @('plan', '-input=false', '-no-color', "-out=$foundationPlan") | Out-Null
  $foundationJson = Plan-Json $roots.foundation $foundationPlan
  $foundationCreates = @($foundationJson.resource_changes | Where-Object { (@($_.change.actions) -join ',') -eq 'create' })
  if ($foundationCreates.Count -ne 4 -or @($foundationJson.resource_changes | Where-Object { 'delete' -in @($_.change.actions) }).Count) { throw 'Foundation plan must contain exactly four non-destructive creates.' }
  Tf $roots.foundation @('apply', '-input=false', '-no-color', $foundationPlan) | Out-Null

  Exact-Tests $roots.fleet 9
  if ($UnitOnly) { Write-Host 'PASS: Challenge 35 exact 12/12 Terraform 1.6 tests with real S3 state and data sources.'; return }

  $fleetPlan = Join-Path $roots.fleet 'fleet.tfplan'
  Tf $roots.fleet @('plan', '-input=false', '-no-color', "-out=$fleetPlan") | Out-Null
  $fleetJson = Plan-Json $roots.fleet $fleetPlan
  $fleetCreates = @($fleetJson.resource_changes | Where-Object { (@($_.change.actions) -join ',') -eq 'create' })
  if ($fleetCreates.Count -ne 6 -or @($fleetJson.resource_changes | Where-Object { 'delete' -in @($_.change.actions) }).Count) { throw 'Fleet plan must contain exactly six non-destructive creates.' }
  Tf $roots.fleet @('apply', '-input=false', '-no-color', $fleetPlan) | Out-Null

  $compute = (Tf $roots.foundation @('output', '-json', 'compute_contract') -Quiet).Text | ConvertFrom-Json
  if ($compute.primary.subnet_id -ne $subnets.primary -or $compute.dr.subnet_id -ne $subnets.dr -or $compute.primary.vpc_id -ne $vpcs.primary -or $compute.dr.vpc_id -ne $vpcs.dr) { throw 'Foundation network contract mismatch.' }
  $contract = (Tf $roots.fleet @('output', '-json', 'fleet_contracts') -Quiet).Text | ConvertFrom-Json
  foreach ($key in @('api@primary', 'api@dr', 'worker@primary')) {
    $item = $contract.$key
    $region = if ($item.role -eq 'dr') { 'us-west-2' } else { 'us-east-1' }
    $expectedSubnet = if ($item.role -eq 'dr') { $subnets.dr } else { $subnets.primary }
    if ($item.subnet_id -ne $expectedSubnet) { throw "$key subnet routing mismatch." }
    $instance = (Aws $region @('ec2', 'describe-instances', '--instance-ids', $item.instance_id, '--query', 'Reservations[0].Instances[0]', '--output', 'json') -Quiet).Text | ConvertFrom-Json
    $tags = @{}; foreach ($tag in $instance.Tags) { $tags[$tag.Key] = $tag.Value }
    if ($tags.RunId -ne $runId -or $tags.Fleet -ne $key -or $tags.LaunchTemplateId -ne $item.launch_template_id -or $instance.SubnetId -ne $expectedSubnet) { throw "$key instance contract mismatch." }
    $lt = (Aws $region @('ec2', 'describe-launch-template-versions', '--launch-template-id', $item.launch_template_id, '--versions', '$Latest', '--query', 'LaunchTemplateVersions[0].LaunchTemplateData', '--output', 'json') -Quiet).Text | ConvertFrom-Json
    if ($lt.InstanceType -ne $item.instance_type) { throw "$key launch-template type mismatch." }
  }

  $reorder = Tf $roots.fleet @('plan', '-detailed-exitcode', '-input=false', '-no-color', '-var=fleet_csv_path=../../fixtures/fleet-reordered.csv') @(0, 2) -Quiet
  if ($reorder.Code -ne 0) { throw 'CSV reorder changed the graph.' }
  $victim = $contract.'api@primary'.instance_id
  Aws 'us-east-1' @('ec2', 'create-tags', '--resources', $victim, '--tags', 'Key=Name,Value=tampered') | Out-Null
  $driftPlan = Join-Path $roots.fleet 'drift.tfplan'
  $drift = Tf $roots.fleet @('plan', '-detailed-exitcode', '-input=false', '-no-color', "-out=$driftPlan") @(0, 2) -Quiet
  if ($drift.Code -ne 2) { throw 'Instance tag drift was not detected.' }
  $driftJson = Plan-Json $roots.fleet $driftPlan
  $updates = @($driftJson.resource_changes | Where-Object { $_.address -eq 'module.primary.aws_instance.fleet["api@primary"]' -and (@($_.change.actions) -join ',') -eq 'update' })
  if ($updates.Count -ne 1 -or @($driftJson.resource_changes | Where-Object { $_.address -ne 'module.primary.aws_instance.fleet["api@primary"]' -and (@($_.change.actions) -join ',') -ne 'no-op' }).Count) { throw 'Drift plan must update only api@primary instance.' }
  Tf $roots.fleet @('apply', '-input=false', '-no-color', $driftPlan) | Out-Null
  foreach ($name in @('foundation', 'fleet')) {
    $clean = Tf $roots[$name] @('plan', '-detailed-exitcode', '-input=false', '-no-color') @(0, 2) -Quiet
    if ($clean.Code -ne 0) { throw "$name plan is not clean." }
  }
  Tf $roots.fleet @('destroy', '-auto-approve', '-input=false', '-no-color') | Out-Null
  Tf $roots.foundation @('destroy', '-auto-approve', '-input=false', '-no-color') | Out-Null
  Aws 'us-east-1' @('s3', 'rb', "s3://$stateBucket", '--force') | Out-Null

  foreach ($region in @('us-east-1', 'us-west-2')) {
    $active = (Aws $region @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text') -Quiet).Text
    $lts = (Aws $region @('ec2', 'describe-launch-templates', '--query', 'LaunchTemplates[].LaunchTemplateName', '--output', 'text') -Quiet).Text
    $sgs = (Aws $region @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text') -Quiet).Text
    if (-not [string]::IsNullOrWhiteSpace($active) -or $lts -match [regex]::Escape("$runId-") -or -not [string]::IsNullOrWhiteSpace($sgs)) { throw "Managed EC2 residue remains in $region." }
  }
  $roles = (Aws 'us-east-1' @('iam', 'list-roles', '--query', "Roles[?contains(RoleName, '$runId')].RoleName", '--output', 'text') -Quiet).Text
  if (-not [string]::IsNullOrWhiteSpace($roles)) { throw 'IAM residue remains.' }
  Write-Host 'PASS: Challenge 35 TF1.6 + two real S3 states + external dual-region network + saved plans/reorder/drift/reverse destroy + zero residue.'
}
catch { $failure = $_ }
finally {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  if ($roots.ContainsKey('fleet') -and (Test-Path -LiteralPath $roots.fleet)) { & terraform "-chdir=$($roots.fleet)" destroy -auto-approve -input=false -no-color 2>$null | Out-Null }
  if ($roots.ContainsKey('foundation') -and (Test-Path -LiteralPath $roots.foundation)) { & terraform "-chdir=$($roots.foundation)" destroy -auto-approve -input=false -no-color 2>$null | Out-Null }
  & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 s3 rb "s3://$stateBucket" --force 2>$null | Out-Null
  if ($subnets.ContainsKey('primary')) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $subnets.primary 2>$null | Out-Null }
  if ($vpcs.ContainsKey('primary')) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $vpcs.primary 2>$null | Out-Null }
  if ($subnets.ContainsKey('dr')) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-subnet --subnet-id $subnets.dr 2>$null | Out-Null }
  if ($vpcs.ContainsKey('dr')) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-vpc --vpc-id $vpcs.dr 2>$null | Out-Null }
  $env:AWS_ACCESS_KEY_ID = $oldA; $env:AWS_SECRET_ACCESS_KEY = $oldS; $env:AWS_DEFAULT_REGION = $oldR
  $env:TF_VAR_run_id = $oldRun; $env:TF_VAR_state_bucket = $oldBucket; $env:TF_VAR_foundation_state_key = $oldKey
  $env:TF_VAR_primary_subnet_id = $oldPrimarySubnet; $env:TF_VAR_dr_subnet_id = $oldDrSubnet
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
  $ErrorActionPreference = $old
}
if ($failure) { throw $failure }
