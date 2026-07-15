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
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $lines = @(& $File @Arguments 2>&1); $code = $LASTEXITCODE
  $ErrorActionPreference = $old; $text = $lines -join "`n"
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
function Action-Map($PlanJson) {
  $map = @{}
  foreach ($change in @($PlanJson.resource_changes)) {
    $action = @($change.change.actions) -join ','
    if ($action -ne 'no-op' -and $action -ne 'read') { $map[$change.address] = $action }
  }
  $map
}
function Assert-Actions($Actual, [hashtable]$Expected, [string]$Label) {
  if ($Actual.Count -ne $Expected.Count) { throw "$Label action count mismatch. actual=$($Actual.Count) expected=$($Expected.Count): $($Actual.Keys -join ', ')" }
  foreach ($address in $Expected.Keys) {
    if (-not $Actual.ContainsKey($address) -or $Actual[$address] -ne $Expected[$address]) { throw "$Label action mismatch at ${address}: actual=$($Actual[$address]) expected=$($Expected[$address])" }
  }
}
function Tags-ToMap($Tags) { $map = @{}; foreach ($tag in @($Tags)) { $map[$tag.Key] = $tag.Value }; $map }

Assert-Endpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if ($files.Count -eq 0 -or @($files | Where-Object Extension -ne '.tf').Count) { throw 'Candidate must contain Terraform HCL only.' }
$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($text -match '(?i)\b(mock_provider|override_data|override_resource|terraform_data|ignore_changes|replica|desired_capacity|min_size|max_size|capacity|shared_credentials|assume_role)\b|AKIA[0-9A-Z]{16}') { throw 'Forbidden mock, workaround, capacity emulation, credential, or test mechanism found.' }
if ([regex]::Matches($text, 'backend\s+"s3"\s*\{\s*\}').Count -ne 2) { throw 'Both roots require empty partial S3 backends.' }
if ([regex]::Matches($text, 'data\s+"terraform_remote_state"').Count -ne 1 -or $text -notmatch 'backend\s*=\s*"s3"') { throw 'Runtime must consume exactly one S3 remote state.' }
$resources = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$data = @([regex]::Matches($text, 'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$allowedResources = @('aws_iam_instance_profile', 'aws_iam_role', 'aws_instance', 'aws_launch_template', 'aws_s3_bucket', 'aws_s3_object', 'aws_security_group')
$allowedData = @('aws_ami', 'aws_iam_policy_document', 'aws_subnet')
if (@($resources | Where-Object { $_ -notin $allowedResources }).Count -or @($data | Where-Object { $_ -notin $allowedData }).Count) { throw "Out-of-syllabus AWS type: resources=$($resources -join ',') data=$($data -join ',')" }
if ($text -match 'resource\s+"aws_(?:vpc|subnet)"') { throw 'Candidate must not manage VPC or subnet.' }
if ($text -notmatch 'output\s+"manifest_guard"[\s\S]*?precondition' -or $text -notmatch 'output\s+"release_guard"[\s\S]*?precondition' -or $text -notmatch 'output\s+"catalog_guard"[\s\S]*?precondition') { throw 'Blocking artifact/release/catalog guards are incomplete.' }
if ([regex]::Matches($text, 'output\s+"manifest_guard"[\s\S]*?precondition').Count -lt 1 -or [regex]::Matches((Get-Content -Raw -LiteralPath (Join-Path $candidatePath 'artifact\outputs.tf')), '\bprecondition\s*\{').Count -lt 6) { throw 'Manifest validation must retain six independent blocking preconditions.' }
if ([regex]::Matches((Get-Content -Raw -LiteralPath (Join-Path $candidatePath 'runtime\outputs.tf')), '\bprecondition\s*\{').Count -lt 8) { throw 'Runtime release/catalog validation must retain independent blocking preconditions.' }
if ($text -notmatch 'data\s+"aws_subnet"\s+"dr"[\s\S]*?provider\s*=\s*aws\.dr' -or $text -notmatch 'data\s+"aws_ami"\s+"dr"[\s\S]*?provider\s*=\s*aws\.dr') { throw 'DR data-source provider routing is incomplete.' }
if ($text -notmatch 'module\s+"primary"[\s\S]*?providers\s*=\s*\{\s*aws\s*=\s*aws\s*\}' -or $text -notmatch 'module\s+"dr"[\s\S]*?providers\s*=\s*\{\s*aws\s*=\s*aws\.dr\s*\}') { throw 'Static module provider routing is incomplete.' }
$childMain = Get-Content -Raw -LiteralPath (Join-Path $candidatePath 'runtime\modules\regional\main.tf')
if ($childMain -match 'provider\s+"aws"') { throw 'Child module must not configure providers.' }
$launchTemplateBlock = [regex]::Match($childMain, 'resource\s+"aws_launch_template"\s+"fleet"')
$instanceBlock = [regex]::Match($childMain, 'resource\s+"aws_instance"\s+"fleet"')
$base64UserData = [regex]::Matches($childMain, 'user_data\s*=\s*base64encode\s*\(\s*jsonencode\s*\(')
$rawUserData = [regex]::Matches($childMain, 'user_data\s*=\s*jsonencode\s*\(')
if (-not $launchTemplateBlock.Success -or -not $instanceBlock.Success -or $base64UserData.Count -ne 1 -or $rawUserData.Count -ne 1 -or
    $base64UserData[0].Index -lt $launchTemplateBlock.Index -or $base64UserData[0].Index -gt $instanceBlock.Index -or
    $rawUserData[0].Index -lt $instanceBlock.Index) {
  throw 'Launch template user_data must be explicit base64 while aws_instance.user_data must be raw provider-encoded text.'
}
if ($childMain -notmatch 'user_data_replace_on_change\s*=\s*true' -or $childMain -notmatch 'create_before_destroy\s*=\s*true') {
  throw 'Boot-time release changes must use an explicit create-before-destroy instance replacement boundary.'
}
foreach ($token in @('contract_version', 'release_version', 'bucket_name', 'artifact_key', 'artifact_digest')) { if ($childMain -notmatch [regex]::Escape($token)) { throw "Runtime user-data contract is missing $token." } }
foreach ($token in @('ArtifactKey', 'ArtifactDigest', 'ReleaseVersion', 'LaunchTemplateId')) { if ($childMain -notmatch [regex]::Escape($token)) { throw "Runtime instance tags are missing $token." } }
if ($childMain -notmatch 'LaunchTemplateId\s*=\s*aws_launch_template\.fleet\[each\.key\]\.id') { throw 'Instance tags must reference the real launch template.' }
$artifactMain = Get-Content -Raw -LiteralPath (Join-Path $candidatePath 'artifact\main.tf')
if ($artifactMain -notmatch 'source_hash\s*=\s*each\.value\.sha256' -or $artifactMain -notmatch 'ArtifactDigest' -or $artifactMain -notmatch 'ReleaseVersion') { throw 'S3 object digest/release contract is incomplete.' }
if ($text -notmatch 'access_key\s*=\s*"test"' -or $text -notmatch 'secret_key\s*=\s*"test"' -or $text -notmatch 'skip_credentials_validation\s*=\s*true' -or $text -notmatch 'skip_metadata_api_check\s*=\s*true' -or $text -notmatch 'skip_requesting_account_id\s*=\s*true') { throw 'Safe LocalStack provider contract missing.' }

$version = (Native 'terraform' @('version', '-json') -Quiet).Text | ConvertFrom-Json
if ($version.terraform_version -notmatch '^1\.6\.') { throw "Terraform 1.6.x required, found $($version.terraform_version)." }
$runId = 'c40' + ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c40-$runId"
$work = Join-Path $temp 'candidate'; $roots = @{}
$stateBucket = "tfpro-c40-state-$runId"; $keys = @{ artifact = 'states/artifact.tfstate'; runtime = 'states/runtime.tfstate' }
$vpcs = @{}; $subnets = @{}; $failure = $null
$oldA = $env:AWS_ACCESS_KEY_ID; $oldS = $env:AWS_SECRET_ACCESS_KEY; $oldR = $env:AWS_DEFAULT_REGION
$oldRun = $env:TF_VAR_run_id; $oldEndpoint = $env:TF_VAR_localstack_endpoint; $oldBucket = $env:TF_VAR_state_bucket; $oldKey = $env:TF_VAR_artifact_state_key
$oldPrimarySubnet = $env:TF_VAR_primary_subnet_id; $oldDrSubnet = $env:TF_VAR_dr_subnet_id
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'
$env:TF_VAR_run_id = $runId; $env:TF_VAR_localstack_endpoint = $LocalstackEndpoint; $env:TF_VAR_state_bucket = $stateBucket; $env:TF_VAR_artifact_state_key = $keys.artifact
try {
  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null } catch { throw 'LocalStack unavailable.' }
  Aws 'us-east-1' @('s3api', 'create-bucket', '--bucket', $stateBucket) | Out-Null
  $vpcs.primary = (Aws 'us-east-1' @('ec2', 'create-vpc', '--cidr-block', '10.140.0.0/16', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text.Trim()
  $subnets.primary = (Aws 'us-east-1' @('ec2', 'create-subnet', '--vpc-id', $vpcs.primary, '--cidr-block', '10.140.1.0/24', '--availability-zone', 'us-east-1a', '--tag-specifications', "ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text.Trim()
  $vpcs.dr = (Aws 'us-west-2' @('ec2', 'create-vpc', '--cidr-block', '10.240.0.0/16', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text.Trim()
  $subnets.dr = (Aws 'us-west-2' @('ec2', 'create-subnet', '--vpc-id', $vpcs.dr, '--cidr-block', '10.240.1.0/24', '--availability-zone', 'us-west-2a', '--tag-specifications', "ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text.Trim()
  $env:TF_VAR_primary_subnet_id = $subnets.primary; $env:TF_VAR_dr_subnet_id = $subnets.dr

  Copy-Clean $candidatePath $work
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\fixtures') -Destination (Join-Path $temp 'fixtures') -Recurse -Force
  foreach ($name in @('artifact', 'runtime')) {
    $roots[$name] = Join-Path $work $name
    New-Item -ItemType Directory -Force (Join-Path $roots[$name] 'tests') | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "$name.tftest.hcl") -Destination (Join-Path $roots[$name] "tests\$name.tftest.hcl")
    Tf $roots[$name] (Backend-Args $stateBucket $keys[$name]) | Out-Null
    Tf $roots[$name] @('fmt', '-check', '-recursive') | Out-Null
    Tf $roots[$name] @('validate', '-no-color') | Out-Null
  }

  Exact-Tests $roots.artifact 8
  $artifactV1Plan = Join-Path $roots.artifact 'artifact-v1.tfplan'
  Tf $roots.artifact @('plan', '-input=false', '-no-color', "-out=$artifactV1Plan") | Out-Null
  Assert-Actions (Action-Map (Plan-Json $roots.artifact $artifactV1Plan)) @{
    'aws_s3_bucket.release' = 'create'
    'aws_s3_object.artifact["api"]' = 'create'
    'aws_s3_object.artifact["worker"]' = 'create'
  } 'artifact v1'
  Tf $roots.artifact @('apply', '-input=false', '-no-color', $artifactV1Plan) | Out-Null

  Exact-Tests $roots.runtime 10
  if ($UnitOnly) { Write-Host 'PASS: Challenge 40 exact 18/18 Terraform 1.6 tests with real S3 remote state and external network data.'; return }

  $runtimeV1Plan = Join-Path $roots.runtime 'runtime-v1.tfplan'
  Tf $roots.runtime @('plan', '-input=false', '-no-color', "-out=$runtimeV1Plan") | Out-Null
  Assert-Actions (Action-Map (Plan-Json $roots.runtime $runtimeV1Plan)) @{
    'aws_iam_role.runtime' = 'create'
    'aws_iam_instance_profile.runtime' = 'create'
    'module.primary.aws_security_group.runtime' = 'create'
    'module.dr.aws_security_group.runtime' = 'create'
    'module.primary.aws_launch_template.fleet["api@primary"]' = 'create'
    'module.dr.aws_launch_template.fleet["worker@dr"]' = 'create'
    'module.primary.aws_instance.fleet["api@primary"]' = 'create'
    'module.dr.aws_instance.fleet["worker@dr"]' = 'create'
  } 'runtime v1'
  Tf $roots.runtime @('apply', '-input=false', '-no-color', $runtimeV1Plan) | Out-Null

  $v1Contract = (Tf $roots.runtime @('output', '-json', 'runtime_contracts') -Quiet).Text | ConvertFrom-Json
  $v1Ids = (Tf $roots.runtime @('output', '-json', 'instance_ids') -Quiet).Text | ConvertFrom-Json
  foreach ($key in @('api@primary', 'worker@dr')) {
    $item = $v1Contract.$key; $region = if ($item.role -eq 'dr') { 'us-west-2' } else { 'us-east-1' }
    $expectedSubnet = if ($item.role -eq 'dr') { $subnets.dr } else { $subnets.primary }
    $instance = (Aws $region @('ec2', 'describe-instances', '--instance-ids', $item.instance_id, '--query', 'Reservations[0].Instances[0]', '--output', 'json') -Quiet).Text | ConvertFrom-Json
    $tags = Tags-ToMap $instance.Tags
    if ($instance.SubnetId -ne $expectedSubnet -or $tags.RunId -ne $runId -or $tags.Fleet -ne $key -or $tags.ReleaseVersion -ne '2026.07.1' -or $tags.ArtifactDigest -ne $item.artifact_digest -or $tags.LaunchTemplateId -ne $item.launch_template_id) { throw "$key v1 instance contract mismatch." }
    $lt = (Aws $region @('ec2', 'describe-launch-template-versions', '--launch-template-id', $item.launch_template_id, '--versions', '$Latest', '--query', 'LaunchTemplateVersions[0].LaunchTemplateData', '--output', 'json') -Quiet).Text | ConvertFrom-Json
    $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($lt.UserData)) | ConvertFrom-Json
    if ($payload.release_version -ne '2026.07.1' -or $payload.artifact_digest -ne $item.artifact_digest -or $payload.artifact_key -ne $item.artifact_key) { throw "$key v1 launch-template payload mismatch." }
  }
  foreach ($name in @('api', 'worker')) {
    $contract = if ($name -eq 'api') { $v1Contract.'api@primary' } else { $v1Contract.'worker@dr' }
    $download = Join-Path $temp "$name-v1.txt"
    Aws 'us-east-1' @('s3api', 'get-object', '--bucket', "$runId-release-artifacts", '--key', $contract.artifact_key, $download) | Out-Null
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $download).Hash.ToLower() -ne $contract.artifact_digest) { throw "$name v1 S3 payload digest mismatch." }
    $objectTags = Tags-ToMap (((Aws 'us-east-1' @('s3api', 'get-object-tagging', '--bucket', "$runId-release-artifacts", '--key', $contract.artifact_key, '--output', 'json') -Quiet).Text | ConvertFrom-Json).TagSet)
    if ($objectTags.ReleaseVersion -ne '2026.07.1' -or $objectTags.ArtifactDigest -ne $contract.artifact_digest -or $objectTags.ArtifactName -ne $name) { throw "$name v1 S3 object tags mismatch." }
  }
  $reorder = Tf $roots.runtime @('plan', '-detailed-exitcode', '-input=false', '-no-color', '-var=runtime_catalog_path=../../fixtures/runtime-reordered.json') @(0, 2) -Quiet
  if ($reorder.Code -ne 0) { throw 'Runtime catalog reorder changed the graph.' }

  $artifactV2Plan = Join-Path $roots.artifact 'artifact-v2.tfplan'
  Tf $roots.artifact @('plan', '-input=false', '-no-color', '-var=manifest_path=../../fixtures/manifest-v2.json', "-out=$artifactV2Plan") | Out-Null
  Assert-Actions (Action-Map (Plan-Json $roots.artifact $artifactV2Plan)) @{
    'aws_s3_object.artifact["api"]' = 'update'
    'aws_s3_object.artifact["worker"]' = 'update'
  } 'artifact v2 rollout'
  Tf $roots.artifact @('apply', '-input=false', '-no-color', $artifactV2Plan) | Out-Null

  $runtimeV2Plan = Join-Path $roots.runtime 'runtime-v2.tfplan'
  Tf $roots.runtime @('plan', '-input=false', '-no-color', "-out=$runtimeV2Plan") | Out-Null
  Assert-Actions (Action-Map (Plan-Json $roots.runtime $runtimeV2Plan)) @{
    'module.primary.aws_launch_template.fleet["api@primary"]' = 'update'
    'module.dr.aws_launch_template.fleet["worker@dr"]' = 'update'
    'module.primary.aws_instance.fleet["api@primary"]' = 'create,delete'
    'module.dr.aws_instance.fleet["worker@dr"]' = 'create,delete'
  } 'runtime v2 rollout'
  Tf $roots.runtime @('apply', '-input=false', '-no-color', $runtimeV2Plan) | Out-Null

  $v2Contract = (Tf $roots.runtime @('output', '-json', 'runtime_contracts') -Quiet).Text | ConvertFrom-Json
  $v2Ids = (Tf $roots.runtime @('output', '-json', 'instance_ids') -Quiet).Text | ConvertFrom-Json
  foreach ($key in @('api@primary', 'worker@dr')) {
    if ($v2Ids.$key -eq $v1Ids.$key) { throw "$key instance identity did not roll across the boot-time release boundary." }
    $item = $v2Contract.$key; $region = if ($item.role -eq 'dr') { 'us-west-2' } else { 'us-east-1' }
    $instance = (Aws $region @('ec2', 'describe-instances', '--instance-ids', $item.instance_id, '--query', 'Reservations[0].Instances[0]', '--output', 'json') -Quiet).Text | ConvertFrom-Json
    $tags = Tags-ToMap $instance.Tags
    if ($tags.ReleaseVersion -ne '2026.07.2' -or $tags.ArtifactDigest -ne $item.artifact_digest) { throw "$key v2 instance tags mismatch." }
    $lt = (Aws $region @('ec2', 'describe-launch-template-versions', '--launch-template-id', $item.launch_template_id, '--versions', '$Latest', '--query', 'LaunchTemplateVersions[0].LaunchTemplateData', '--output', 'json') -Quiet).Text | ConvertFrom-Json
    $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($lt.UserData)) | ConvertFrom-Json
    if ($payload.release_version -ne '2026.07.2' -or $payload.artifact_digest -ne $item.artifact_digest) { throw "$key v2 launch-template payload mismatch." }
  }
  foreach ($name in @('api', 'worker')) {
    $contract = if ($name -eq 'api') { $v2Contract.'api@primary' } else { $v2Contract.'worker@dr' }
    $download = Join-Path $temp "$name-v2.txt"
    Aws 'us-east-1' @('s3api', 'get-object', '--bucket', "$runId-release-artifacts", '--key', $contract.artifact_key, $download) | Out-Null
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $download).Hash.ToLower() -ne $contract.artifact_digest) { throw "$name v2 S3 payload digest mismatch." }
    $objectTags = Tags-ToMap (((Aws 'us-east-1' @('s3api', 'get-object-tagging', '--bucket', "$runId-release-artifacts", '--key', $contract.artifact_key, '--output', 'json') -Quiet).Text | ConvertFrom-Json).TagSet)
    if ($objectTags.ReleaseVersion -ne '2026.07.2' -or $objectTags.ArtifactDigest -ne $contract.artifact_digest -or $objectTags.ArtifactName -ne $name) { throw "$name v2 S3 object tags mismatch." }
  }

  Aws 'us-east-1' @('ec2', 'create-tags', '--resources', $v2Ids.'api@primary', '--tags', 'Key=Name,Value=tampered') | Out-Null
  $driftPlan = Join-Path $roots.runtime 'drift.tfplan'
  $drift = Tf $roots.runtime @('plan', '-detailed-exitcode', '-input=false', '-no-color', "-out=$driftPlan") @(0, 2) -Quiet
  if ($drift.Code -ne 2) { throw 'Runtime instance tag drift was not detected.' }
  Assert-Actions (Action-Map (Plan-Json $roots.runtime $driftPlan)) @{ 'module.primary.aws_instance.fleet["api@primary"]' = 'update' } 'runtime drift'
  Tf $roots.runtime @('apply', '-input=false', '-no-color', $driftPlan) | Out-Null
  $runtimeClean = Tf $roots.runtime @('plan', '-detailed-exitcode', '-input=false', '-no-color') @(0, 2) -Quiet
  if ($runtimeClean.Code -ne 0) { throw 'Runtime plan is not clean after rollout repair.' }
  $artifactClean = Tf $roots.artifact @('plan', '-detailed-exitcode', '-input=false', '-no-color', '-var=manifest_path=../../fixtures/manifest-v2.json') @(0, 2) -Quiet
  if ($artifactClean.Code -ne 0) { throw 'Artifact plan is not clean at v2.' }

  Tf $roots.runtime @('destroy', '-auto-approve', '-input=false', '-no-color') | Out-Null
  Tf $roots.artifact @('destroy', '-auto-approve', '-input=false', '-no-color', '-var=manifest_path=../../fixtures/manifest-v2.json') | Out-Null
  Aws 'us-east-1' @('s3', 'rb', "s3://$stateBucket", '--force') | Out-Null
  foreach ($region in @('us-east-1', 'us-west-2')) {
    $active = (Aws $region @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text') -Quiet).Text
    $lts = (Aws $region @('ec2', 'describe-launch-templates', '--query', 'LaunchTemplates[].LaunchTemplateName', '--output', 'text') -Quiet).Text
    $sgs = (Aws $region @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text') -Quiet).Text
    if (-not [string]::IsNullOrWhiteSpace($active) -or $lts -match [regex]::Escape("$runId-") -or -not [string]::IsNullOrWhiteSpace($sgs)) { throw "Runtime residue remains in $region." }
  }
  $buckets = (Aws 'us-east-1' @('s3api', 'list-buckets', '--query', 'Buckets[].Name', '--output', 'text') -Quiet).Text
  $roles = (Aws 'us-east-1' @('iam', 'list-roles', '--query', "Roles[?contains(RoleName, '$runId')].RoleName", '--output', 'text') -Quiet).Text
  if ($buckets -match [regex]::Escape("$runId-release-artifacts") -or -not [string]::IsNullOrWhiteSpace($roles)) { throw 'Artifact or IAM residue remains.' }
  Write-Host 'PASS: Challenge 40 TF1.6 + two real S3 states + v1/v2 strict action contracts + dual-region LocalStack verification + reorder/drift/reverse destroy + zero residue.'
}
catch { $failure = $_ }
finally {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  if ($roots.ContainsKey('runtime') -and (Test-Path -LiteralPath $roots.runtime)) { & terraform "-chdir=$($roots.runtime)" destroy -auto-approve -input=false -no-color 2>$null | Out-Null }
  if ($roots.ContainsKey('artifact') -and (Test-Path -LiteralPath $roots.artifact)) { & terraform "-chdir=$($roots.artifact)" destroy -auto-approve -input=false -no-color '-var=manifest_path=../../fixtures/manifest-v2.json' 2>$null | Out-Null }
  & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 s3 rb "s3://$stateBucket" --force 2>$null | Out-Null
  if ($subnets.ContainsKey('primary')) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $subnets.primary 2>$null | Out-Null }
  if ($vpcs.ContainsKey('primary')) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $vpcs.primary 2>$null | Out-Null }
  if ($subnets.ContainsKey('dr')) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-subnet --subnet-id $subnets.dr 2>$null | Out-Null }
  if ($vpcs.ContainsKey('dr')) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-vpc --vpc-id $vpcs.dr 2>$null | Out-Null }
  $env:AWS_ACCESS_KEY_ID = $oldA; $env:AWS_SECRET_ACCESS_KEY = $oldS; $env:AWS_DEFAULT_REGION = $oldR
  $env:TF_VAR_run_id = $oldRun; $env:TF_VAR_localstack_endpoint = $oldEndpoint; $env:TF_VAR_state_bucket = $oldBucket; $env:TF_VAR_artifact_state_key = $oldKey
  $env:TF_VAR_primary_subnet_id = $oldPrimarySubnet; $env:TF_VAR_dr_subnet_id = $oldDrSubnet
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
  $ErrorActionPreference = $old
}
if ($failure) { throw $failure }
