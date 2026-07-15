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
  if ($Value -notmatch '^https?://(?:localhost|127\.0\.0\.1|\[::1\]):[0-9]{1,5}$') { throw "Unsafe endpoint: $Value" }
  try { $uri = [Uri]$Value } catch { throw "Invalid endpoint: $Value" }
  if (-not $uri.IsAbsoluteUri -or $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535) {
    throw "Unsafe endpoint: $Value"
  }
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $lines = @(& $File @Arguments 2>&1); $code = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
  $text = $lines -join "`n"
  if (-not $Quiet -and $lines.Count) { $lines | Out-Host }
  if ($code -notin $Allowed) { throw "$File failed ($code): $($Arguments -join ' ')`n$text" }
  [pscustomobject]@{ Code = $code; Text = $text }
}

function Invoke-Terraform([string]$Directory, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  Invoke-Native 'terraform' (@("-chdir=$Directory") + $Arguments) $Allowed -Quiet:$Quiet
}

function Invoke-Aws([string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  Invoke-Native 'aws.exe' (@('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1') + $Arguments) $Allowed -Quiet:$Quiet
}

function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force $Destination | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if ($item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') -or $item.Extension -in @('.tfplan', '.tfstate')) { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
  }
}

function Get-PlanJson([string]$Directory, [string]$PlanPath) {
  (Invoke-Terraform $Directory @('show', '-json', $PlanPath) -Quiet).Text | ConvertFrom-Json
}

function Get-ActionMap($PlanJson) {
  $map = @{}
  foreach ($change in @($PlanJson.resource_changes)) {
    $action = @($change.change.actions) -join ','
    if ($action -notin @('no-op', 'read')) { $map[$change.address] = $action }
  }
  $map
}

function Assert-ExactMap($Actual, $Expected, [string]$Label) {
  if ($Actual.Count -ne $Expected.Count) { throw "$Label action count mismatch: $($Actual.Count) vs $($Expected.Count)." }
  foreach ($key in $Expected.Keys) {
    if (-not $Actual.ContainsKey($key) -or $Actual[$key] -ne $Expected[$key]) {
      throw "$Label action mismatch for $key. Expected $($Expected[$key]); got $($Actual[$key])."
    }
  }
}

Assert-Endpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$candidateFiles = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if ($candidateFiles.Count -eq 0 -or @($candidateFiles | Where-Object { $_.Extension -ne '.tf' }).Count -ne 0) { throw 'Candidate must contain Terraform HCL only.' }
$candidateText = ($candidateFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
if ($candidateText -match '(?i)TODO|mock_provider|override_(?:resource|data|module)|terraform_data|ignore_changes|resource\s+"aws_(?:vpc|subnet)"|AKIA[0-9A-Z]{16}') { throw 'Candidate is unfinished or uses a forbidden workaround.' }

$resources = @([regex]::Matches($candidateText, 'resource\s+"([a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$dataSources = @([regex]::Matches($candidateText, 'data\s+"([a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($resources -join ',') -ne 'aws_instance,aws_launch_template,aws_security_group,random_integer') { throw "Unexpected resources: $($resources -join ',')" }
if (($dataSources -join ',') -ne 'aws_ami,aws_subnet') { throw "Unexpected data sources: $($dataSources -join ',')" }
foreach ($token in @('for_each = local.fleets_by_id', 'keepers = {', 'placement_epoch', 'user_data_replace_on_change = true', 'create_before_destroy = true', 'LaunchTemplateId', 'precondition')) {
  if ($candidateText -notmatch [regex]::Escape($token)) { throw "Missing canary contract token: $token" }
}
if ([regex]::Matches($candidateText, 'for_each\s*=\s*local\.fleets_by_id').Count -ne 4) { throw 'Exactly four fleet-keyed resource graphs are required.' }
if ($candidateText -notmatch 'access_key\s*=\s*"test"' -or $candidateText -notmatch 'secret_key\s*=\s*"test"' -or $candidateText -notmatch 'skip_credentials_validation\s*=\s*true' -or $candidateText -notmatch 'skip_metadata_api_check\s*=\s*true' -or $candidateText -notmatch 'skip_requesting_account_id\s*=\s*true') { throw 'Safe LocalStack provider contract is missing.' }

$version = (Invoke-Native 'terraform' @('version', '-json') -Quiet).Text | ConvertFrom-Json
if ($version.terraform_version -ne '1.6.6') { throw "Terraform 1.6.6 is required; got $($version.terraform_version)." }
if ($null -eq (Get-Command aws.exe -ErrorAction SilentlyContinue)) { throw 'AWS CLI v2 is required.' }

$runId = 'c56' + ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c56-$runId"
$work = Join-Path $temp 'candidate'
$vpcId = $null
$subnets = @()
$failure = $null
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$oldSubnets = $env:TF_VAR_subnet_ids
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'

try {
  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null } catch { throw 'LocalStack is unavailable.' }
  $vpcId = (Invoke-Aws @('ec2', 'create-vpc', '--cidr-block', '10.156.0.0/16', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text.Trim()
  $public = (Invoke-Aws @('ec2', 'create-subnet', '--vpc-id', $vpcId, '--cidr-block', '10.156.1.0/24', '--availability-zone', 'us-east-1a', '--tag-specifications', "ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text.Trim()
  $private = (Invoke-Aws @('ec2', 'create-subnet', '--vpc-id', $vpcId, '--cidr-block', '10.156.2.0/24', '--availability-zone', 'us-east-1b', '--tag-specifications', "ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text.Trim()
  $subnets = @($public, $private)
  $env:TF_VAR_subnet_ids = (@{ 'public-a' = $public; 'private-a' = $private } | ConvertTo-Json -Compress)

  Copy-Clean $candidatePath $work
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\fixtures') -Destination (Join-Path $temp 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force (Join-Path $work 'tests') | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $work 'tests\canonical.tftest.hcl')

  Invoke-Terraform $work @('fmt', '-check', '-recursive') | Out-Null
  Invoke-Terraform $work @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Invoke-Terraform $work @('validate', '-no-color') | Out-Null
  $tests = Invoke-Terraform $work @('test', '-test-directory=tests', '-no-color', "-var=run_id=$runId", '-var=name_prefix=tfpro-c56')
  if ([regex]::Matches($tests.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 13 -or $tests.Text -notmatch '(?m)^Success!\s+13 passed,\s+0 failed\.\s*$') { throw 'Expected exact 13/13 canonical tests.' }
  if ($UnitOnly) { Write-Host 'PASS: Challenge 56 exact 13/13 Terraform 1.6.6 tests.'; return }

  Remove-Item -LiteralPath (Join-Path $work 'tests') -Recurse -Force
  $common = @('-input=false', '-no-color', "-var=run_id=$runId", '-var=name_prefix=tfpro-c56', '-var=environment=prod')
  $v1Path = Join-Path $work 'v1.tfplan'
  Invoke-Terraform $work (@('plan', "-out=$v1Path", '-var=fleet_csv_path=../fixtures/fleets.csv') + $common) | Out-Null
  $expectedCreates = @{}
  foreach ($fleet in @('api', 'worker')) {
    $expectedCreates["random_integer.placement[`"$fleet`"]"] = 'create'
    $expectedCreates["aws_security_group.fleet[`"$fleet`"]"] = 'create'
    $expectedCreates["aws_launch_template.fleet[`"$fleet`"]"] = 'create'
    $expectedCreates["aws_instance.fleet[`"$fleet`"]"] = 'create'
  }
  Assert-ExactMap (Get-ActionMap (Get-PlanJson $work $v1Path)) $expectedCreates 'v1'
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $v1Path) | Out-Null

  $v1Contract = (Invoke-Terraform $work @('output', '-json', 'fleet_contract') -Quiet).Text | ConvertFrom-Json
  $v1Ids = @{}
  foreach ($fleet in @('api', 'worker')) {
    $contract = $v1Contract.fleets.$fleet
    $v1Ids[$fleet] = $contract.instance_id
    if ($contract.subnet_id -notin $subnets -or $contract.vpc_id -ne $vpcId -or $contract.placement_index -notin @(0, 1)) { throw "$fleet placement contract is invalid." }
    $instance = (Invoke-Aws @('ec2', 'describe-instances', '--instance-ids', $contract.instance_id, '--query', 'Reservations[0].Instances[0]', '--output', 'json') -Quiet).Text | ConvertFrom-Json
    $tags = @{}; foreach ($tag in $instance.Tags) { $tags[$tag.Key] = $tag.Value }
    if ($instance.SubnetId -ne $contract.subnet_id -or $instance.ImageId -ne $v1Contract.ami_id -or $tags.RunId -ne $runId -or $tags.FleetId -ne $fleet -or $tags.LaunchTemplateId -ne $contract.launch_template_id) { throw "$fleet instance readback mismatch." }
    $template = (Invoke-Aws @('ec2', 'describe-launch-template-versions', '--launch-template-id', $contract.launch_template_id, '--versions', '$Latest', '--query', 'LaunchTemplateVersions[0].LaunchTemplateData', '--output', 'json') -Quiet).Text | ConvertFrom-Json
    if ($template.ImageId -ne $v1Contract.ami_id -or $template.InstanceType -ne $contract.instance_type) { throw "$fleet launch-template readback mismatch." }
  }

  $reorder = Invoke-Terraform $work (@('plan', '-detailed-exitcode', '-var=fleet_csv_path=../fixtures/fleets-reordered.csv') + $common) @(0, 2) -Quiet
  if ($reorder.Code -ne 0) { throw "CSV reorder changed the graph.`n$($reorder.Text)" }

  $rotatedPath = Join-Path $work 'rotated.tfplan'
  $rotated = Invoke-Terraform $work (@('plan', '-detailed-exitcode', "-out=$rotatedPath", '-var=fleet_csv_path=../fixtures/fleets-rotated.csv') + $common) @(0, 2) -Quiet
  if ($rotated.Code -ne 2) { throw 'placement_epoch change was not detected.' }
  $rotatedActions = Get-ActionMap (Get-PlanJson $work $rotatedPath)
  $expectedRotation = @{
    'random_integer.placement["api"]' = 'create,delete'
    'aws_instance.fleet["api"]'       = 'create,delete'
  }
  Assert-ExactMap $rotatedActions $expectedRotation 'rotation'
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $rotatedPath) | Out-Null
  $rotatedContract = (Invoke-Terraform $work @('output', '-json', 'fleet_contract') -Quiet).Text | ConvertFrom-Json
  if ($rotatedContract.fleets.api.instance_id -eq $v1Ids.api -or $rotatedContract.fleets.worker.instance_id -ne $v1Ids.worker) { throw 'Rotation did not replace only the api instance.' }

  $victim = $rotatedContract.fleets.worker.instance_id
  Invoke-Aws @('ec2', 'create-tags', '--resources', $victim, '--tags', 'Key=Name,Value=tampered') | Out-Null
  $driftPath = Join-Path $work 'drift.tfplan'
  $drift = Invoke-Terraform $work (@('plan', '-detailed-exitcode', "-out=$driftPath", '-var=fleet_csv_path=../fixtures/fleets-rotated.csv') + $common) @(0, 2) -Quiet
  if ($drift.Code -ne 2) { throw 'Instance tag drift was not detected.' }
  Assert-ExactMap (Get-ActionMap (Get-PlanJson $work $driftPath)) @{ 'aws_instance.fleet["worker"]' = 'update' } 'drift'
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $driftPath) | Out-Null

  $clean = Invoke-Terraform $work (@('plan', '-detailed-exitcode', '-var=fleet_csv_path=../fixtures/fleets-rotated.csv') + $common) @(0, 2) -Quiet
  if ($clean.Code -ne 0) { throw 'Post-repair plan is not clean.' }
  $destroyPath = Join-Path $work 'destroy.tfplan'
  Invoke-Terraform $work (@('plan', '-destroy', "-out=$destroyPath", '-var=fleet_csv_path=../fixtures/fleets-rotated.csv') + $common) | Out-Null
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $destroyPath) | Out-Null

  $securityGroups = (Invoke-Aws @('ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text') -Quiet).Text
  $instances = (Invoke-Aws @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text') -Quiet).Text
  $templates = (Invoke-Aws @('ec2', 'describe-launch-templates', '--query', 'LaunchTemplates[].LaunchTemplateName', '--output', 'text') -Quiet).Text
  if (-not [string]::IsNullOrWhiteSpace($securityGroups) -or -not [string]::IsNullOrWhiteSpace($instances) -or $templates -match "tfpro-c56-(api|worker)-$runId") { throw 'Challenge-owned EC2 residue remains.' }
  Write-Host 'PASS: Challenge 56 TF1.6.6 + random placement + saved plans + reorder/rotation/drift + zero residue.'
}
catch { $failure = $_ }
finally {
  $oldPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  if (Test-Path -LiteralPath $work) {
    & terraform "-chdir=$work" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" '-var=name_prefix=tfpro-c56' '-var=environment=prod' '-var=fleet_csv_path=../fixtures/fleets-rotated.csv' 2>$null | Out-Null
  }
  foreach ($subnet in $subnets) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $subnet 2>$null | Out-Null }
  if ($vpcId) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $vpcId 2>$null | Out-Null }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  $env:TF_VAR_subnet_ids = $oldSubnets
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
  $ErrorActionPreference = $oldPreference
}
if ($failure) { throw $failure }
