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
function Copy-Fixtures([string]$Destination) {
  $target = Join-Path $Destination 'fixtures'; Copy-Item (Join-Path $PSScriptRoot '..\fixtures') $target -Recurse -Force
  $states = Join-Path $target 'states'
  foreach ($fixture in Get-ChildItem -LiteralPath $states -Filter '*.fixture.json' -File) {
    $runtimeName = $fixture.Name -replace '\.fixture\.json$', '.tfstate'
    Copy-Item -LiteralPath $fixture.FullName -Destination (Join-Path $states $runtimeName) -Force
  }
}
function Install-Test([string]$Root, [string]$Name) {
  $testDir = Join-Path $Root 'tests'; New-Item -ItemType Directory -Force $testDir | Out-Null
  Copy-Item (Join-Path $PSScriptRoot "$Name.tftest.hcl") (Join-Path $testDir 'canonical.tftest.hcl')
}
function Plan-Json([string]$Directory, [string]$Plan) { (Tf $Directory @('show', '-json', $Plan) -Quiet).Text | ConvertFrom-Json }
function Action-Map($Json) { $map = @{}; foreach ($change in @($Json.resource_changes)) { $action = @($change.change.actions) -join ','; if ($action -notin @('no-op', 'read')) { $map[$change.address] = $action } }; $map }
function Assert-Map($Actual, [hashtable]$Expected, [string]$Label) {
  if ($Actual.Count -ne $Expected.Count) { throw "$Label action count mismatch: $($Actual.Keys -join ', ')" }
  foreach ($key in $Expected.Keys) { if (-not $Actual.ContainsKey($key) -or $Actual[$key] -ne $Expected[$key]) { throw "$Label action mismatch at ${key}: $($Actual[$key])" } }
}
function Tag-Map($Tags) { $map = @{}; foreach ($tag in @($Tags)) { $map[$tag.Key] = $tag.Value }; $map }
function Split-Ids([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
  @($Value -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
function Assert-Rejected($Result, [string]$Pattern, [string]$Label) {
  if ($Result.Code -ne 1) { throw "$Label did not fail with exit 1." }
  if ($Result.Text -notmatch $Pattern) { throw "$Label failed for the wrong reason.`n$($Result.Text)" }
}
function Assert-ActivePlacement([string]$ExpectedRegion) {
  $east = @(Split-Ids (Aws 'us-east-1' @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text') -Quiet).Text)
  $west = @(Split-Ids (Aws 'us-west-2' @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text') -Quiet).Text)
  if ($ExpectedRegion -eq 'primary' -and ($east.Count -ne 1 -or $west.Count -ne 0)) { throw "Converged primary placement must be east=1/west=0; got east=$($east.Count)/west=$($west.Count)." }
  if ($ExpectedRegion -eq 'dr' -and ($east.Count -ne 0 -or $west.Count -ne 1)) { throw "Converged DR placement must be east=0/west=1; got east=$($east.Count)/west=$($west.Count)." }
}
function Assert-InstanceContract([string]$Region, [string]$InstanceId, [string]$RegionKey, $Foundation, $Regional) {
  $instance = (Aws $Region @('ec2', 'describe-instances', '--instance-ids', $InstanceId, '--query', 'Reservations[0].Instances[0]', '--output', 'json') -Quiet).Text | ConvertFrom-Json
  $isPrimary = $RegionKey -eq 'primary'
  $expectedSubnet = if ($isPrimary) { $Regional.primary_subnet_id } else { $Regional.dr_subnet_id }
  $expectedAmi = if ($isPrimary) { $Regional.primary_ami_id } else { $Regional.dr_ami_id }
  $expectedType = if ($isPrimary) { $Regional.primary_instance_type } else { $Regional.dr_instance_type }
  $expectedGroup = if ($isPrimary) { $Regional.primary_security_group_id } else { $Regional.dr_security_group_id }
  $expectedBucket = if ($isPrimary) { $Foundation.primary_bucket } else { $Foundation.dr_bucket }
  $groups = @($instance.SecurityGroups | ForEach-Object { $_.GroupId })
  $tags = Tag-Map $instance.Tags
  if (
    $instance.SubnetId -ne $expectedSubnet -or $instance.ImageId -ne $expectedAmi -or $instance.InstanceType -ne $expectedType -or
    $groups.Count -ne 1 -or $groups[0] -ne $expectedGroup -or $instance.IamInstanceProfile.Arn -notmatch "/$([regex]::Escape($Foundation.profile_name))$" -or
    $tags.ActiveRegion -ne $RegionKey -or $tags.RunId -ne $runId
  ) { throw "$RegionKey active instance did not consume the exact regional scalar contract." }
  $encoded = ((Aws $Region @('ec2', 'describe-instance-attribute', '--instance-id', $InstanceId, '--attribute', 'userData', '--query', 'UserData.Value', '--output', 'text') -Quiet).Text).Trim()
  if (-not $encoded -or $encoded -eq 'None') { throw "$RegionKey active instance has no user data." }
  try { $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded)) | ConvertFrom-Json } catch { throw "$RegionKey active instance user data is not canonical base64 JSON." }
  $fields = @($payload.PSObject.Properties.Name | Sort-Object)
  if (($fields -join ',') -ne 'artifact_key,artifact_sha256,bucket,foundation_contract_id,generation,regional_contract_id') { throw "$RegionKey active user-data fields are not exact: $($fields -join ',')." }
  if (
    $payload.artifact_key -ne $Foundation.artifact_key -or $payload.artifact_sha256 -ne $Foundation.artifact_sha256 -or $payload.bucket -ne $expectedBucket -or
    [int]$payload.generation -ne [int]$Foundation.generation -or $payload.foundation_contract_id -ne $Foundation.contract_id -or
    $payload.regional_contract_id -ne $Regional.regional_contract_id
  ) { throw "$RegionKey active user data did not preserve the artifact and two-layer lineage contract." }
}
function Best-Effort-Aws([string]$Region, [string[]]$Arguments) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & aws.exe --endpoint-url $LocalstackEndpoint --region $Region @Arguments 2>$null | Out-Null
  $ErrorActionPreference = $old
}
function Best-Effort-AwsText([string]$Region, [string[]]$Arguments) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $lines = @(& aws.exe --endpoint-url $LocalstackEndpoint --region $Region @Arguments 2>$null)
  $ErrorActionPreference = $old
  ($lines -join "`n").Trim()
}
function Probe-Aws([string]$Region, [string[]]$Arguments) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $lines = @(& aws.exe --endpoint-url $LocalstackEndpoint --region $Region @Arguments 2>&1); $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  [pscustomobject]@{ Code = $code; Region = $Region; Arguments = ($Arguments -join ' '); Text = (($lines -join "`n").Trim()) }
}
function Invoke-FallbackCleanup([string]$ScopeRunId, [string]$EastAmiId, [string]$WestAmiId, [string]$EastSubnetId, [string]$WestSubnetId, [string]$EastVpcId, [string]$WestVpcId) {
  foreach ($region in @('us-east-1', 'us-west-2')) {
    $instances = @(Split-Ids (Best-Effort-AwsText $region @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$ScopeRunId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text')))
    if ($instances.Count) { Best-Effort-Aws $region (@('ec2', 'terminate-instances', '--instance-ids') + $instances) }
  }
  foreach ($region in @('us-east-1', 'us-west-2')) {
    foreach ($attempt in 1..20) {
      $active = @(Split-Ids (Best-Effort-AwsText $region @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$ScopeRunId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text')))
      if (-not $active.Count) { break }
      Start-Sleep -Milliseconds 250
    }
    $templates = @(Split-Ids (Best-Effort-AwsText $region @('ec2', 'describe-launch-templates', '--query', "LaunchTemplates[?contains(LaunchTemplateName, '$ScopeRunId')].LaunchTemplateId", '--output', 'text')))
    foreach ($template in $templates) { Best-Effort-Aws $region @('ec2', 'delete-launch-template', '--launch-template-id', $template) }
  }
  foreach ($attempt in 1..3) {
    foreach ($region in @('us-east-1', 'us-west-2')) {
      $groups = @(Split-Ids (Best-Effort-AwsText $region @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$ScopeRunId", '--query', 'SecurityGroups[].GroupId', '--output', 'text')))
      foreach ($group in $groups) { Best-Effort-Aws $region @('ec2', 'delete-security-group', '--group-id', $group) }
    }
    Start-Sleep -Milliseconds 300
  }

  $buckets = @(Split-Ids (Best-Effort-AwsText 'us-east-1' @('s3api', 'list-buckets', '--query', "Buckets[?contains(Name, '$ScopeRunId')].Name", '--output', 'text')))
  foreach ($bucket in $buckets) { Best-Effort-Aws 'us-east-1' @('s3', 'rb', "s3://$bucket", '--force') }

  $profiles = @(Split-Ids (Best-Effort-AwsText 'us-east-1' @('iam', 'list-instance-profiles', '--query', "InstanceProfiles[?contains(InstanceProfileName, '$ScopeRunId')].InstanceProfileName", '--output', 'text')))
  foreach ($profile in $profiles) {
    $profileRoles = @(Split-Ids (Best-Effort-AwsText 'us-east-1' @('iam', 'get-instance-profile', '--instance-profile-name', $profile, '--query', 'InstanceProfile.Roles[].RoleName', '--output', 'text')))
    foreach ($role in $profileRoles) { Best-Effort-Aws 'us-east-1' @('iam', 'remove-role-from-instance-profile', '--instance-profile-name', $profile, '--role-name', $role) }
    Best-Effort-Aws 'us-east-1' @('iam', 'delete-instance-profile', '--instance-profile-name', $profile)
  }
  $roles = @(Split-Ids (Best-Effort-AwsText 'us-east-1' @('iam', 'list-roles', '--query', "Roles[?contains(RoleName, '$ScopeRunId')].RoleName", '--output', 'text')))
  foreach ($role in $roles) {
    $managedPolicies = @(Split-Ids (Best-Effort-AwsText 'us-east-1' @('iam', 'list-attached-role-policies', '--role-name', $role, '--query', 'AttachedPolicies[].PolicyArn', '--output', 'text')))
    foreach ($policy in $managedPolicies) { Best-Effort-Aws 'us-east-1' @('iam', 'detach-role-policy', '--role-name', $role, '--policy-arn', $policy) }
    $inlinePolicies = @(Split-Ids (Best-Effort-AwsText 'us-east-1' @('iam', 'list-role-policies', '--role-name', $role, '--query', 'PolicyNames', '--output', 'text')))
    foreach ($policy in $inlinePolicies) { Best-Effort-Aws 'us-east-1' @('iam', 'delete-role-policy', '--role-name', $role, '--policy-name', $policy) }
    Best-Effort-Aws 'us-east-1' @('iam', 'delete-role', '--role-name', $role)
  }

  $external = @(
    [pscustomobject]@{ Region = 'us-east-1'; Ami = $EastAmiId; Subnet = $EastSubnetId; Vpc = $EastVpcId },
    [pscustomobject]@{ Region = 'us-west-2'; Ami = $WestAmiId; Subnet = $WestSubnetId; Vpc = $WestVpcId }
  )
  foreach ($item in $external) {
    $images = @(Split-Ids (Best-Effort-AwsText $item.Region @('ec2', 'describe-images', '--owners', 'self', '--filters', "Name=name,Values=$ScopeRunId-*", '--query', 'Images[].ImageId', '--output', 'text')))
    if ($item.Ami) { $images += $item.Ami }; foreach ($imageId in @($images | Sort-Object -Unique)) { Best-Effort-Aws $item.Region @('ec2', 'deregister-image', '--image-id', $imageId) }
  }
  foreach ($attempt in 1..3) {
    foreach ($item in $external) {
      $subnets = @(Split-Ids (Best-Effort-AwsText $item.Region @('ec2', 'describe-subnets', '--filters', "Name=tag:RunId,Values=$ScopeRunId", '--query', 'Subnets[].SubnetId', '--output', 'text')))
      if ($item.Subnet) { $subnets += $item.Subnet }; foreach ($subnetId in @($subnets | Sort-Object -Unique)) { Best-Effort-Aws $item.Region @('ec2', 'delete-subnet', '--subnet-id', $subnetId) }
      $vpcs = @(Split-Ids (Best-Effort-AwsText $item.Region @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$ScopeRunId", '--query', 'Vpcs[].VpcId', '--output', 'text')))
      if ($item.Vpc) { $vpcs += $item.Vpc }; foreach ($vpcId in @($vpcs | Sort-Object -Unique)) { Best-Effort-Aws $item.Region @('ec2', 'delete-vpc', '--vpc-id', $vpcId) }
    }
    Start-Sleep -Milliseconds 300
  }
}

Assert-Endpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if (-not $files.Count -or @($files | Where-Object Extension -ne '.tf').Count) { throw 'Candidate must contain HCL only.' }
$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($text -match '(?i)\b(terraform_data|mock_provider|override_data|override_resource|aws_autoscaling_group|ignore_changes|shared_credentials|assume_role)\b|terraform\s+(?:state|output)\s|AKIA[0-9A-Z]{16}') { throw 'Forbidden workaround, ASG, state CLI, mock, or credential mechanism found.' }
$types = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$expectedTypes = 'aws_iam_instance_profile,aws_iam_role,aws_instance,aws_launch_template,aws_s3_bucket,aws_s3_object,aws_security_group'
if (($types -join ',') -ne $expectedTypes) { throw "Unexpected managed AWS types: $($types -join ',')" }
if ($text -match 'resource\s+"aws_(?:vpc|subnet)"') { throw 'VPC/subnet must remain external.' }
if ([regex]::Matches($text, 'data\s+"terraform_remote_state"').Count -ne 3) { throw 'Exactly three remote-state data sources are required across consumers.' }
$promotionText = (Get-ChildItem -LiteralPath (Join-Path $candidatePath 'promotion') -Filter '*.tf' -File | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($promotionText -match '(?m)^\s*launch_template\s*\{') { throw 'Promotion instances must use direct scalar contracts, not LT association.' }
foreach ($token in @(
  'providers = { aws = aws.dr }', 'owners      = ["self"]', 'resource "aws_instance" "active_primary"', 'resource "aws_instance" "active_dr"',
  'user_data_replace_on_change = true', 'iam_instance_profile', 'vpc_security_group_ids', 'expected_foundation_id', 'expected_regional_id',
  'resource "aws_launch_template" "release"', 'resource "aws_s3_object" "dr"'
)) { if ($text -notmatch [regex]::Escape($token)) { throw "Missing capstone contract token: $token" } }
$moduleText = (Get-ChildItem -LiteralPath (Join-Path $candidatePath 'regional\modules\region') -Filter '*.tf' -File | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($moduleText -match '(?m)^\s*provider\s+"') { throw 'Regional child module must not configure a provider.' }
if ([regex]::Matches($text, 'access_key\s*=\s*"test"').Count -lt 6 -or [regex]::Matches($text, 'secret_key\s*=\s*"test"').Count -lt 6 -or
    [regex]::Matches($text, 'skip_credentials_validation\s*=\s*true').Count -lt 6 -or [regex]::Matches($text, 'skip_metadata_api_check\s*=\s*true').Count -lt 6 -or
    [regex]::Matches($text, 'skip_requesting_account_id\s*=\s*true').Count -lt 6) { throw 'Every provider instance must use the safe LocalStack contract.' }
$versionText = (Native 'terraform' @('version', '-json') -Quiet).Text; $version = $versionText.Substring($versionText.IndexOf('{')) | ConvertFrom-Json
if ($version.terraform_version -ne '1.6.6') { throw "Terraform 1.6.6 required, found $($version.terraform_version)." }

$runId = 'c60' + ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c60-$runId"; $foundation = Join-Path $temp 'foundation'; $regional = Join-Path $temp 'regional'; $promotion = Join-Path $temp 'promotion'
$eastVpc = $null; $eastSubnet = $null; $drVpc = $null; $drSubnet = $null; $eastAmi = $null; $drAmi = $null; $failure = $null
$foundationCommon = @(); $regionalCommon = @(); $promotionCommon = @()
$successMessage = $null
$oldAccess = $env:AWS_ACCESS_KEY_ID; $oldSecret = $env:AWS_SECRET_ACCESS_KEY; $oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'
try {
  try { Invoke-WebRequest -UseBasicParsing "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null } catch { throw 'LocalStack is unavailable.' }
  $eastVpc = ((Aws 'us-east-1' @('ec2', 'create-vpc', '--cidr-block', '10.160.0.0/24', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text).Trim()
  $eastSubnet = ((Aws 'us-east-1' @('ec2', 'create-subnet', '--vpc-id', $eastVpc, '--cidr-block', '10.160.0.0/28', '--tag-specifications', "ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text).Trim()
  $drVpc = ((Aws 'us-west-2' @('ec2', 'create-vpc', '--cidr-block', '10.161.0.0/24', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text).Trim()
  $drSubnet = ((Aws 'us-west-2' @('ec2', 'create-subnet', '--vpc-id', $drVpc, '--cidr-block', '10.161.0.0/28', '--tag-specifications', "ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text).Trim()
  $eastAmi = ((Aws 'us-east-1' @('ec2', 'register-image', '--name', "$runId-release-east", '--architecture', 'x86_64', '--root-device-name', '/dev/sda1', '--block-device-mappings', 'DeviceName=/dev/sda1,Ebs={VolumeSize=8,DeleteOnTermination=true,VolumeType=gp2}', '--tag-specifications', "ResourceType=image,Tags=[{Key=RunId,Value=$runId}]", '--query', 'ImageId', '--output', 'text') -Quiet).Text).Trim()
  $drAmi = ((Aws 'us-west-2' @('ec2', 'register-image', '--name', "$runId-release-dr", '--architecture', 'x86_64', '--root-device-name', '/dev/sda1', '--block-device-mappings', 'DeviceName=/dev/sda1,Ebs={VolumeSize=8,DeleteOnTermination=true,VolumeType=gp2}', '--tag-specifications', "ResourceType=image,Tags=[{Key=RunId,Value=$runId}]", '--query', 'ImageId', '--output', 'text') -Quiet).Text).Trim()

  Copy-Clean (Join-Path $candidatePath 'foundation') $foundation; Copy-Clean (Join-Path $candidatePath 'regional') $regional; Copy-Clean (Join-Path $candidatePath 'promotion') $promotion
  foreach ($root in @($foundation, $regional, $promotion)) { Copy-Fixtures $root; Tf $root @('fmt', '-check', '-recursive') | Out-Null; Tf $root @('init', '-backend=false', '-input=false', '-no-color') | Out-Null; Tf $root @('validate', '-no-color') | Out-Null }
  Install-Test $foundation 'foundation'; Install-Test $regional 'regional'; Install-Test $promotion 'promotion'

  $foundationTests = Tf $foundation @('test', '-test-directory=tests', '-no-color')
  $regionalTests = Tf $regional @('test', '-test-directory=tests', '-no-color', "-var=primary_subnet_id=$eastSubnet", "-var=dr_subnet_id=$drSubnet", "-var=primary_ami_pattern=$runId-release-east", "-var=dr_ami_pattern=$runId-release-dr")
  $promotionTests = Tf $promotion @('test', '-test-directory=tests', '-no-color')
  $allTests = "$($foundationTests.Text)`n$($regionalTests.Text)`n$($promotionTests.Text)"
  if ([regex]::Matches($allTests, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 16 -or [regex]::Matches($allTests, '(?m)^Success!').Count -ne 3) { throw 'Expected exact 16/16 canonical tests across three roots.' }
  if ($UnitOnly) { $successMessage = 'PASS: Challenge 60 score 95, exact 16/16 Terraform 1.6.6 tests.' }
  else {

  $foundationCommon = @('-input=false', '-no-color', "-var=run_id=$runId", '-var=manifest_path=fixtures/release.json')
  $foundationPlan = Join-Path $foundation 'create.tfplan'; Tf $foundation (@('plan', "-out=$foundationPlan") + $foundationCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $foundation $foundationPlan)) @{
    'aws_s3_bucket.primary' = 'create'; 'aws_s3_object.primary' = 'create'; 'aws_s3_bucket.dr' = 'create'; 'aws_s3_object.dr' = 'create';
    'aws_iam_role.release' = 'create'; 'aws_iam_instance_profile.release' = 'create'
  } 'foundation create'
  Tf $foundation @('apply', '-input=false', '-no-color', $foundationPlan) | Out-Null
  $foundationContract = (Tf $foundation @('output', '-json', 'foundation_contract') -Quiet).Text | ConvertFrom-Json
  $bodyPath = Join-Path $temp 'artifact.bin'; Aws 'us-east-1' @('s3api', 'get-object', '--bucket', $foundationContract.primary_bucket, '--key', $foundationContract.artifact_key, $bodyPath) | Out-Null
  if ((Get-FileHash -LiteralPath $bodyPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $foundationContract.artifact_sha256) { throw 'Primary artifact digest mismatch.' }
  Remove-Item -LiteralPath $bodyPath -Force; Aws 'us-west-2' @('s3api', 'get-object', '--bucket', $foundationContract.dr_bucket, '--key', $foundationContract.artifact_key, $bodyPath) | Out-Null
  if ((Get-FileHash -LiteralPath $bodyPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $foundationContract.artifact_sha256) { throw 'DR artifact digest mismatch.' }
  $profileRole = ((Aws 'us-east-1' @('iam', 'get-instance-profile', '--instance-profile-name', $foundationContract.profile_name, '--query', 'InstanceProfile.Roles[0].RoleName', '--output', 'text') -Quiet).Text).Trim()
  if ($profileRole -ne $foundationContract.role_name) { throw 'Shared identity contract mismatch.' }
  $reorderFoundation = Tf $foundation (@('plan', '-detailed-exitcode', '-var=manifest_path=fixtures/release-reordered.json') + $foundationCommon[0..2]) @(0, 2) -Quiet
  if ($reorderFoundation.Code -ne 0) { throw 'Release manifest key reorder changed foundation.' }

  $foundationState = Join-Path $foundation 'terraform.tfstate'
  $regionalCommon = @('-input=false', '-no-color', "-var=foundation_state_path=$foundationState", "-var=expected_run_id=$runId", '-var=minimum_generation=7', "-var=primary_subnet_id=$eastSubnet", "-var=dr_subnet_id=$drSubnet", "-var=primary_ami_pattern=$runId-release-east", "-var=dr_ami_pattern=$runId-release-dr")
  $regionalPlan = Join-Path $regional 'create.tfplan'; Tf $regional (@('plan', "-out=$regionalPlan") + $regionalCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $regional $regionalPlan)) @{
    'module.primary.aws_security_group.release' = 'create'; 'module.primary.aws_launch_template.release' = 'create';
    'module.dr.aws_security_group.release' = 'create'; 'module.dr.aws_launch_template.release' = 'create'
  } 'regional create'
  Tf $regional @('apply', '-input=false', '-no-color', $regionalPlan) | Out-Null
  $regionalContract = (Tf $regional @('output', '-json', 'regional_contract') -Quiet).Text | ConvertFrom-Json
  foreach ($regionSpec in @(
      @('us-east-1', 'primary', $regionalContract.primary_launch_template_id, $foundationContract.primary_bucket, $regionalContract.primary_ami_id, $regionalContract.primary_instance_type, $regionalContract.primary_security_group_id),
      @('us-west-2', 'dr', $regionalContract.dr_launch_template_id, $foundationContract.dr_bucket, $regionalContract.dr_ami_id, $regionalContract.dr_instance_type, $regionalContract.dr_security_group_id)
    )) {
    $lt = (Aws $regionSpec[0] @('ec2', 'describe-launch-template-versions', '--launch-template-id', $regionSpec[2], '--versions', '$Default', '--query', 'LaunchTemplateVersions[0].LaunchTemplateData', '--output', 'json') -Quiet).Text | ConvertFrom-Json
    $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($lt.UserData)) | ConvertFrom-Json
    $ltGroups = @($lt.SecurityGroupIds)
    if (
      $lt.IamInstanceProfile.Name -ne $foundationContract.profile_name -or $lt.ImageId -ne $regionSpec[4] -or $lt.InstanceType -ne $regionSpec[5] -or
      $ltGroups.Count -ne 1 -or $ltGroups[0] -ne $regionSpec[6] -or $payload.bucket -ne $regionSpec[3] -or
      $payload.artifact_key -ne $foundationContract.artifact_key -or $payload.artifact_sha256 -ne $foundationContract.artifact_sha256 -or $payload.generation -ne 7
    ) { throw "$($regionSpec[1]) launch-template contract mismatch." }
  }
  $cleanRegional = Tf $regional (@('plan', '-detailed-exitcode') + $regionalCommon) @(0, 2) -Quiet; if ($cleanRegional.Code -ne 0) { throw 'Regional state is not clean.' }
  $regionalFixtureCommon = @('-input=false', '-no-color', '-var=minimum_generation=7', "-var=primary_subnet_id=$eastSubnet", "-var=dr_subnet_id=$drSubnet", "-var=primary_ami_pattern=$runId-release-east", "-var=dr_ami_pattern=$runId-release-dr")
  $foreignRegional = Tf $regional (@('plan', '-var=foundation_state_path=fixtures/states/foundation-foreign.tfstate', "-var=expected_run_id=$runId") + $regionalFixtureCommon) @(1) -Quiet
  $staleRegional = Tf $regional (@('plan', '-var=foundation_state_path=fixtures/states/foundation-stale.tfstate', '-var=expected_run_id=fixture01') + $regionalFixtureCommon) @(1) -Quiet
  $missingRegional = Tf $regional (@('plan', '-var=foundation_state_path=fixtures/states/foundation-missing.tfstate', '-var=expected_run_id=fixture01') + $regionalFixtureCommon) @(1) -Quiet
  $tamperedRegional = Tf $regional (@('plan', '-var=foundation_state_path=fixtures/states/foundation-tampered.tfstate', '-var=expected_run_id=fixture01') + $regionalFixtureCommon) @(1) -Quiet
  Assert-Rejected $foreignRegional '(?i)(foreign|tampered|lineage)' 'Regional foreign-state rejection'
  Assert-Rejected $staleRegional '(?i)(stale|freshness)' 'Regional stale-state rejection'
  Assert-Rejected $missingRegional '(?i)schema' 'Regional missing-schema rejection'
  Assert-Rejected $tamperedRegional '(?i)(tampered|lineage)' 'Regional tampered-contract rejection'

  $regionalState = Join-Path $regional 'terraform.tfstate'
  $promotionCommon = @('-input=false', '-no-color', "-var=foundation_state_path=$foundationState", "-var=regional_state_path=$regionalState", "-var=expected_run_id=$runId", '-var=minimum_generation=7')
  $primaryPlan = Join-Path $promotion 'primary.tfplan'; Tf $promotion (@('plan', "-out=$primaryPlan", '-var=active_region=primary') + $promotionCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $promotion $primaryPlan)) @{ 'aws_instance.active_primary[0]' = 'create' } 'primary promotion'
  Tf $promotion @('apply', '-input=false', '-no-color', $primaryPlan) | Out-Null
  $primaryContract = (Tf $promotion @('output', '-json', 'active_contract') -Quiet).Text | ConvertFrom-Json
  Assert-InstanceContract 'us-east-1' $primaryContract.instance_id 'primary' $foundationContract $regionalContract
  Assert-ActivePlacement 'primary'
  $foreignPromotion = Tf $promotion @('plan', '-input=false', '-no-color', "-var=foundation_state_path=$foundationState", '-var=regional_state_path=fixtures/states/regional-foreign.tfstate', "-var=expected_run_id=$runId", '-var=minimum_generation=7', '-var=active_region=primary') @(1) -Quiet
  $stalePromotion = Tf $promotion @('plan', '-input=false', '-no-color', '-var=foundation_state_path=fixtures/states/foundation-stale.tfstate', '-var=regional_state_path=fixtures/states/regional-stale.tfstate', '-var=expected_run_id=fixture01', '-var=minimum_generation=7', '-var=active_region=primary') @(1) -Quiet
  Assert-Rejected $foreignPromotion '(?i)(foreign|tampered|disconnected|lineage)' 'Promotion foreign-state rejection'
  Assert-Rejected $stalePromotion '(?i)(stale|mismatched|generation|freshness)' 'Promotion stale-state rejection'

  $failoverPlan = Join-Path $promotion 'failover.tfplan'; Tf $promotion (@('plan', "-out=$failoverPlan", '-var=active_region=dr') + $promotionCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $promotion $failoverPlan)) @{ 'aws_instance.active_primary[0]' = 'delete'; 'aws_instance.active_dr[0]' = 'create' } 'DR failover'
  Tf $promotion @('apply', '-input=false', '-no-color', $failoverPlan) | Out-Null
  $drContract = (Tf $promotion @('output', '-json', 'active_contract') -Quiet).Text | ConvertFrom-Json
  Assert-InstanceContract 'us-west-2' $drContract.instance_id 'dr' $foundationContract $regionalContract
  Assert-ActivePlacement 'dr'

  $recoveryPlan = Join-Path $promotion 'recovery.tfplan'; Tf $promotion (@('plan', "-out=$recoveryPlan", '-var=active_region=primary') + $promotionCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $promotion $recoveryPlan)) @{ 'aws_instance.active_dr[0]' = 'delete'; 'aws_instance.active_primary[0]' = 'create' } 'primary recovery'
  Tf $promotion @('apply', '-input=false', '-no-color', $recoveryPlan) | Out-Null
  $recovered = (Tf $promotion @('output', '-json', 'active_contract') -Quiet).Text | ConvertFrom-Json
  Assert-InstanceContract 'us-east-1' $recovered.instance_id 'primary' $foundationContract $regionalContract
  Assert-ActivePlacement 'primary'
  Aws 'us-east-1' @('ec2', 'create-tags', '--resources', $recovered.instance_id, '--tags', 'Key=Name,Value=tampered') | Out-Null
  $driftPlan = Join-Path $promotion 'drift.tfplan'; $drift = Tf $promotion (@('plan', '-detailed-exitcode', "-out=$driftPlan", '-var=active_region=primary') + $promotionCommon) @(0, 2) -Quiet; if ($drift.Code -ne 2) { throw 'Active instance drift was not detected.' }
  Assert-Map (Action-Map (Plan-Json $promotion $driftPlan)) @{ 'aws_instance.active_primary[0]' = 'update' } 'active drift'
  Tf $promotion @('apply', '-input=false', '-no-color', $driftPlan) | Out-Null; Assert-ActivePlacement 'primary'; $cleanPromotion = Tf $promotion (@('plan', '-detailed-exitcode', '-var=active_region=primary') + $promotionCommon) @(0, 2) -Quiet; if ($cleanPromotion.Code -ne 0) { throw 'Promotion state is not clean.' }

  $promotionDestroy = Join-Path $promotion 'destroy.tfplan'; Tf $promotion (@('plan', '-destroy', "-out=$promotionDestroy", '-var=active_region=primary') + $promotionCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $promotion $promotionDestroy)) @{ 'aws_instance.active_primary[0]' = 'delete' } 'promotion destroy'; Tf $promotion @('apply', '-input=false', '-no-color', $promotionDestroy) | Out-Null
  $regionalDestroy = Join-Path $regional 'destroy.tfplan'; Tf $regional (@('plan', '-destroy', "-out=$regionalDestroy") + $regionalCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $regional $regionalDestroy)) @{
    'module.primary.aws_security_group.release' = 'delete'; 'module.primary.aws_launch_template.release' = 'delete';
    'module.dr.aws_security_group.release' = 'delete'; 'module.dr.aws_launch_template.release' = 'delete'
  } 'regional destroy'; Tf $regional @('apply', '-input=false', '-no-color', $regionalDestroy) | Out-Null
  $foundationDestroy = Join-Path $foundation 'destroy.tfplan'; Tf $foundation (@('plan', '-destroy', "-out=$foundationDestroy") + $foundationCommon) | Out-Null
  Assert-Map (Action-Map (Plan-Json $foundation $foundationDestroy)) @{
    'aws_s3_bucket.primary' = 'delete'; 'aws_s3_object.primary' = 'delete'; 'aws_s3_bucket.dr' = 'delete'; 'aws_s3_object.dr' = 'delete';
    'aws_iam_role.release' = 'delete'; 'aws_iam_instance_profile.release' = 'delete'
  } 'foundation destroy'; Tf $foundation @('apply', '-input=false', '-no-color', $foundationDestroy) | Out-Null

  Aws 'us-east-1' @('ec2', 'deregister-image', '--image-id', $eastAmi) | Out-Null
  Aws 'us-west-2' @('ec2', 'deregister-image', '--image-id', $drAmi) | Out-Null
  Aws 'us-east-1' @('ec2', 'delete-subnet', '--subnet-id', $eastSubnet) | Out-Null
  Aws 'us-west-2' @('ec2', 'delete-subnet', '--subnet-id', $drSubnet) | Out-Null
  Aws 'us-east-1' @('ec2', 'delete-vpc', '--vpc-id', $eastVpc) | Out-Null
  Aws 'us-west-2' @('ec2', 'delete-vpc', '--vpc-id', $drVpc) | Out-Null

  $residue = [ordered]@{
    east_active  = (Aws 'us-east-1' @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text') -Quiet).Text
    west_active  = (Aws 'us-west-2' @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text') -Quiet).Text
    east_sg      = (Aws 'us-east-1' @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text') -Quiet).Text
    west_sg      = (Aws 'us-west-2' @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text') -Quiet).Text
    east_lt      = (Aws 'us-east-1' @('ec2', 'describe-launch-templates', '--query', "LaunchTemplates[?contains(LaunchTemplateName, '$runId')].LaunchTemplateId", '--output', 'text') -Quiet).Text
    west_lt      = (Aws 'us-west-2' @('ec2', 'describe-launch-templates', '--query', "LaunchTemplates[?contains(LaunchTemplateName, '$runId')].LaunchTemplateId", '--output', 'text') -Quiet).Text
    east_ami     = (Aws 'us-east-1' @('ec2', 'describe-images', '--owners', 'self', '--filters', "Name=name,Values=$runId-*", '--query', 'Images[].ImageId', '--output', 'text') -Quiet).Text
    west_ami     = (Aws 'us-west-2' @('ec2', 'describe-images', '--owners', 'self', '--filters', "Name=name,Values=$runId-*", '--query', 'Images[].ImageId', '--output', 'text') -Quiet).Text
    east_ami_id  = (Aws 'us-east-1' @('ec2', 'describe-images', '--owners', 'self', '--filters', "Name=image-id,Values=$eastAmi", '--query', 'Images[].ImageId', '--output', 'text') -Quiet).Text
    west_ami_id  = (Aws 'us-west-2' @('ec2', 'describe-images', '--owners', 'self', '--filters', "Name=image-id,Values=$drAmi", '--query', 'Images[].ImageId', '--output', 'text') -Quiet).Text
    east_subnet  = (Aws 'us-east-1' @('ec2', 'describe-subnets', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Subnets[].SubnetId', '--output', 'text') -Quiet).Text
    west_subnet  = (Aws 'us-west-2' @('ec2', 'describe-subnets', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Subnets[].SubnetId', '--output', 'text') -Quiet).Text
    east_subnet_id = (Aws 'us-east-1' @('ec2', 'describe-subnets', '--filters', "Name=subnet-id,Values=$eastSubnet", '--query', 'Subnets[].SubnetId', '--output', 'text') -Quiet).Text
    west_subnet_id = (Aws 'us-west-2' @('ec2', 'describe-subnets', '--filters', "Name=subnet-id,Values=$drSubnet", '--query', 'Subnets[].SubnetId', '--output', 'text') -Quiet).Text
    east_vpc     = (Aws 'us-east-1' @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Vpcs[].VpcId', '--output', 'text') -Quiet).Text
    west_vpc     = (Aws 'us-west-2' @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Vpcs[].VpcId', '--output', 'text') -Quiet).Text
    east_vpc_id  = (Aws 'us-east-1' @('ec2', 'describe-vpcs', '--filters', "Name=vpc-id,Values=$eastVpc", '--query', 'Vpcs[].VpcId', '--output', 'text') -Quiet).Text
    west_vpc_id  = (Aws 'us-west-2' @('ec2', 'describe-vpcs', '--filters', "Name=vpc-id,Values=$drVpc", '--query', 'Vpcs[].VpcId', '--output', 'text') -Quiet).Text
    buckets      = (Aws 'us-east-1' @('s3api', 'list-buckets', '--query', "Buckets[?contains(Name, '$runId')].Name", '--output', 'text') -Quiet).Text
    roles        = (Aws 'us-east-1' @('iam', 'list-roles', '--query', "Roles[?contains(RoleName, '$runId')].RoleName", '--output', 'text') -Quiet).Text
    profiles     = (Aws 'us-east-1' @('iam', 'list-instance-profiles', '--query', "InstanceProfiles[?contains(InstanceProfileName, '$runId')].InstanceProfileName", '--output', 'text') -Quiet).Text
  }
  $remaining = @($residue.GetEnumerator() | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Value) })
  if ($remaining.Count) { throw "Run-scoped cross-region residue remains: $($remaining.Name -join ', ')." }
  $successMessage = 'PASS: Challenge 60 score 95 + exact 16/16 + three-state DR promotion/recovery + converged active exact-one + reverse saved destroy + zero residue.'
  }
} catch { $failure = $_ } finally {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  if ((Test-Path (Join-Path $promotion 'terraform.tfstate')) -and $promotionCommon.Count) { & terraform "-chdir=$promotion" destroy -auto-approve @promotionCommon '-var=active_region=primary' 2>$null | Out-Null }
  if ((Test-Path (Join-Path $regional 'terraform.tfstate')) -and $regionalCommon.Count) { & terraform "-chdir=$regional" destroy -auto-approve @regionalCommon 2>$null | Out-Null }
  if ((Test-Path (Join-Path $foundation 'terraform.tfstate')) -and $foundationCommon.Count) { & terraform "-chdir=$foundation" destroy -auto-approve @foundationCommon 2>$null | Out-Null }
  Invoke-FallbackCleanup $runId $eastAmi $drAmi $eastSubnet $drSubnet $eastVpc $drVpc
  $cleanupProbes = @(
    Probe-Aws 'us-east-1' @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text')
    Probe-Aws 'us-west-2' @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text')
    Probe-Aws 'us-east-1' @('ec2', 'describe-launch-templates', '--query', "LaunchTemplates[?contains(LaunchTemplateName, '$runId')].LaunchTemplateId", '--output', 'text')
    Probe-Aws 'us-west-2' @('ec2', 'describe-launch-templates', '--query', "LaunchTemplates[?contains(LaunchTemplateName, '$runId')].LaunchTemplateId", '--output', 'text')
    Probe-Aws 'us-east-1' @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text')
    Probe-Aws 'us-west-2' @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text')
    Probe-Aws 'us-east-1' @('ec2', 'describe-images', '--owners', 'self', '--filters', "Name=name,Values=$runId-*", '--query', 'Images[].ImageId', '--output', 'text')
    Probe-Aws 'us-west-2' @('ec2', 'describe-images', '--owners', 'self', '--filters', "Name=name,Values=$runId-*", '--query', 'Images[].ImageId', '--output', 'text')
    Probe-Aws 'us-east-1' @('ec2', 'describe-subnets', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Subnets[].SubnetId', '--output', 'text')
    Probe-Aws 'us-west-2' @('ec2', 'describe-subnets', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Subnets[].SubnetId', '--output', 'text')
    Probe-Aws 'us-east-1' @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Vpcs[].VpcId', '--output', 'text')
    Probe-Aws 'us-west-2' @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Vpcs[].VpcId', '--output', 'text')
    Probe-Aws 'us-east-1' @('s3api', 'list-buckets', '--query', "Buckets[?contains(Name, '$runId')].Name", '--output', 'text')
    Probe-Aws 'us-east-1' @('iam', 'list-roles', '--query', "Roles[?contains(RoleName, '$runId')].RoleName", '--output', 'text')
    Probe-Aws 'us-east-1' @('iam', 'list-instance-profiles', '--query', "InstanceProfiles[?contains(InstanceProfileName, '$runId')].InstanceProfileName", '--output', 'text')
  )
  if ($eastAmi) { $cleanupProbes += Probe-Aws 'us-east-1' @('ec2', 'describe-images', '--owners', 'self', '--filters', "Name=image-id,Values=$eastAmi", '--query', 'Images[].ImageId', '--output', 'text') }
  if ($drAmi) { $cleanupProbes += Probe-Aws 'us-west-2' @('ec2', 'describe-images', '--owners', 'self', '--filters', "Name=image-id,Values=$drAmi", '--query', 'Images[].ImageId', '--output', 'text') }
  if ($eastSubnet) { $cleanupProbes += Probe-Aws 'us-east-1' @('ec2', 'describe-subnets', '--filters', "Name=subnet-id,Values=$eastSubnet", '--query', 'Subnets[].SubnetId', '--output', 'text') }
  if ($drSubnet) { $cleanupProbes += Probe-Aws 'us-west-2' @('ec2', 'describe-subnets', '--filters', "Name=subnet-id,Values=$drSubnet", '--query', 'Subnets[].SubnetId', '--output', 'text') }
  if ($eastVpc) { $cleanupProbes += Probe-Aws 'us-east-1' @('ec2', 'describe-vpcs', '--filters', "Name=vpc-id,Values=$eastVpc", '--query', 'Vpcs[].VpcId', '--output', 'text') }
  if ($drVpc) { $cleanupProbes += Probe-Aws 'us-west-2' @('ec2', 'describe-vpcs', '--filters', "Name=vpc-id,Values=$drVpc", '--query', 'Vpcs[].VpcId', '--output', 'text') }
  $cleanupProblems = @()
  foreach ($probe in $cleanupProbes) {
    if ($probe.Code -ne 0) { $cleanupProblems += "$($probe.Region) [$($probe.Arguments)] exit=$($probe.Code)" }
    elseif (-not [string]::IsNullOrWhiteSpace($probe.Text)) { $cleanupProblems += "$($probe.Region) [$($probe.Arguments)] residue=$($probe.Text)" }
  }
  if ($cleanupProblems.Count) {
    $cleanupText = "Cleanup verification failed: $($cleanupProblems -join '; ')"
    if ($failure) {
      $original = if ($failure -is [System.Management.Automation.ErrorRecord]) { $failure.Exception } elseif ($failure -is [Exception]) { $failure } else { $null }
      $failure = if ($original) { [InvalidOperationException]::new("$([string]$failure)`n$cleanupText", $original) } else { [InvalidOperationException]::new("$([string]$failure)`n$cleanupText") }
    } else { $failure = [InvalidOperationException]::new($cleanupText) }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess; $env:AWS_SECRET_ACCESS_KEY = $oldSecret; $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }; $ErrorActionPreference = $old
}
if ($failure) { throw $failure }
if ($successMessage) { Write-Host $successMessage }
