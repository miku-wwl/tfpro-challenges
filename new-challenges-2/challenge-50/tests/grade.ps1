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
  try { $uri = [Uri]$Value } catch { throw "Invalid LocalStack endpoint: $Value" }
  if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http', 'https') -or
      $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or
      $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or
      $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535) {
    throw "Unsafe LocalStack endpoint: $Value"
  }
}

function Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $lines = @(& $File @Arguments 2>&1 | ForEach-Object { "$_" })
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  $text = $lines -join "`n"
  if (-not $Quiet -and $lines.Count -gt 0) { $lines | Out-Host }
  if ($code -notin $Allowed) {
    throw "$File $($Arguments -join ' ') failed ($code).`n$text"
  }
  [pscustomobject]@{ Code = $code; Text = $text }
}

function Tf([string]$Directory, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  Native 'terraform' (@("-chdir=$Directory") + $Arguments) $Allowed -Quiet:$Quiet
}

function Aws([string]$Region, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  Native 'aws.exe' (@('--endpoint-url', $LocalstackEndpoint, '--region', $Region) + $Arguments) $Allowed -Quiet:$Quiet
}

function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force $Destination | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if ($item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup', '.terraform.tfstate.lock.info') -or
        $item.Extension -in @('.tfplan', '.tfstate')) {
      continue
    }
    $target = Join-Path $Destination $item.Name
    if ($item.PSIsContainer) {
      Copy-Clean $item.FullName $target
    } else {
      Copy-Item -LiteralPath $item.FullName -Destination $target -Force
    }
  }
}

function Write-Backend([string]$Path, [string]$Bucket, [string]$Key) {
  [IO.File]::WriteAllText($Path, @"
bucket = "$Bucket"
key = "$Key"
region = "us-east-1"
access_key = "test"
secret_key = "test"
use_path_style = true
skip_credentials_validation = true
skip_metadata_api_check = true
skip_requesting_account_id = true
endpoints = { s3 = "$LocalstackEndpoint" }
"@, [Text.UTF8Encoding]::new($false))
}

function Exact-Tests([string]$Directory, [string]$File, [int]$Expected) {
  $testDirectory = Join-Path $Directory 'tests'
  New-Item -ItemType Directory -Force $testDirectory | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $File) -Destination (Join-Path $testDirectory $File) -Force
  $result = Tf $Directory @('test', '-test-directory=tests', '-no-color')
  $summaryCount = [regex]::Matches($result.Text, "(?m)^Success!\s+$Expected passed,\s+0 failed\.\s*$").Count
  $passCount = [regex]::Matches($result.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count
  if ($summaryCount -ne 1 -or $passCount -ne $Expected) {
    throw "Expected exact $Expected/$Expected normal Terraform 1.6.6 runs for $File."
  }
  Remove-Item -LiteralPath $testDirectory -Recurse -Force
}

function Plan-Json([string]$Directory, [string]$Plan) {
  ((Tf $Directory @('show', '-json', $Plan) -Quiet).Text | ConvertFrom-Json)
}

function Assert-Changes($Document, [hashtable]$Expected, [string]$Label) {
  $actual = @{}
  foreach ($change in @($Document.resource_changes | Where-Object { [string]$_.address -notlike 'data.*' })) {
    $actions = @($change.change.actions) -join ','
    if ($actions -ne 'no-op') { $actual[[string]$change.address] = $actions }
  }
  if ($actual.Count -ne $Expected.Count) {
    throw "$Label expected $($Expected.Count) changes, got $($actual.Count): $($actual.Keys -join ', ')"
  }
  foreach ($address in $Expected.Keys) {
    if (-not $actual.ContainsKey($address) -or $actual[$address] -ne $Expected[$address]) {
      throw "$Label expected $address=$($Expected[$address]); got $($actual[$address])."
    }
  }
}

function Assert-Clean([string]$Directory, [string[]]$Arguments, [string]$Label) {
  $result = Tf $Directory (@('plan', '-detailed-exitcode') + $Arguments) @(0, 2) -Quiet
  if ($result.Code -ne 0) { throw "$Label is not clean.`n$($result.Text)" }
}

Assert-Endpoint $LocalstackEndpoint
$version = ((Native 'terraform' @('version', '-json') -Quiet).Text | ConvertFrom-Json).terraform_version
if ($version -ne '1.6.6') { throw "Terraform 1.6.6 is required; active version is $version." }

$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
$identitySource = Join-Path $candidateRoot 'identity'
$platformSource = Join-Path $candidateRoot 'platform'
$workloadSource = Join-Path $candidateRoot 'workload'
foreach ($root in @($identitySource, $platformSource, $workloadSource)) {
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Candidate must contain identity, platform, and workload roots.' }
}

$candidateFiles = @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -File)
if (@($candidateFiles | Where-Object Extension -ne '.tf').Count -ne 0) { throw 'Candidate may contain Terraform HCL only.' }
$all = ($candidateFiles | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($all -match '(?i)\b(TODO|terraform_data|mock_provider|override_data|override_resource|aws_sns_|aws_vpc|aws_subnets|aws_ami)\b|ignore_changes') {
  throw 'Forbidden TODO, synthetic resource, mock, SNS, VPC/AMI discovery, or drift suppression found.'
}
if ([regex]::Matches($all, 'required_version\s*=\s*"~> 1\.6"').Count -ne 4 -or
    [regex]::Matches($all, 'backend\s+"s3"\s*\{\s*\}').Count -ne 3) {
  throw 'All three roots require Terraform ~>1.6 and empty partial S3 backends.'
}

$identityText = (Get-ChildItem $identitySource -Recurse -Filter *.tf | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$platformText = (Get-ChildItem $platformSource -Recurse -Filter *.tf | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$workloadText = (Get-ChildItem $workloadSource -Recurse -Filter *.tf | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$identityResources = @([regex]::Matches($identityText, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$platformResources = @([regex]::Matches($platformText, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$workloadResources = @([regex]::Matches($workloadText, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$workloadData = @([regex]::Matches($workloadText, 'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($identityResources -join ',') -ne 'aws_iam_instance_profile,aws_iam_policy,aws_iam_role,aws_iam_role_policy_attachment') { throw "Identity resources are not exact: $($identityResources -join ',')" }
if (($platformResources -join ',') -ne 'aws_s3_bucket,aws_s3_object') { throw "Platform resources are not exact: $($platformResources -join ',')" }
if (($workloadResources -join ',') -ne 'aws_instance') { throw "Workload resources are not exact: $($workloadResources -join ',')" }
if (($workloadData -join ',') -ne 'aws_subnet') { throw "Only data.aws_subnet is allowed in workload; got $($workloadData -join ',')" }
if ([regex]::Matches($platformText, 'data\s+"terraform_remote_state"').Count -ne 1 -or
    [regex]::Matches($workloadText, 'data\s+"terraform_remote_state"').Count -ne 2) {
  throw 'The platform/workload S3 remote-state chain is incomplete.'
}
if ([regex]::Matches($workloadText, 'provider\s+"aws"\s*\{').Count -ne 2 -or
    $workloadText -notmatch 'alias\s*=\s*"dr"' -or
    $workloadText -notmatch 'module\s+"dr"[\s\S]*?aws\s*=\s*aws\.dr') {
  throw 'Explicit dual-region provider routing is incomplete.'
}
if ($workloadText -notmatch 'user_data_replace_on_change\s*=\s*true') { throw 'Release propagation must replace instances through the official EC2 argument.' }
foreach ($piece in @($platformText, $workloadText)) {
  foreach ($field in @('access_key', 'secret_key', 'use_path_style', 'skip_credentials_validation', 'skip_metadata_api_check', 'skip_requesting_account_id', 'endpoints')) {
    if ($piece -notmatch "(?m)^\s*$field\s*=") { throw "Remote-state config misses $field." }
  }
}

$identityTests = Get-Content -Raw (Join-Path $PSScriptRoot 'identity.tftest.hcl')
$platformTests = Get-Content -Raw (Join-Path $PSScriptRoot 'platform.tftest.hcl')
$workloadTests = Get-Content -Raw (Join-Path $PSScriptRoot 'workload.tftest.hcl')
if (($identityTests + $platformTests + $workloadTests) -match '(?i)mock_provider|override_' -or
    [regex]::Matches($identityTests, '(?m)^run\s+"').Count -ne 4 -or
    [regex]::Matches($platformTests, '(?m)^run\s+"').Count -ne 7 -or
    [regex]::Matches($workloadTests, '(?m)^run\s+"').Count -ne 8) {
  throw 'Canonical tests must be exact 4+7+8 normal Terraform 1.6.6 runs.'
}

$suffix = ([Guid]::NewGuid().ToString('N')).Substring(0, 10)
$runId = "c50-$suffix"
$stateBucket = "tfpro-c50-state-$suffix"
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c50-$suffix"
$candidateWork = Join-Path $temp 'candidate'
$identityWork = Join-Path $candidateWork 'identity'
$platformWork = Join-Path $candidateWork 'platform'
$workloadWork = Join-Path $candidateWork 'workload'
$primaryVpc = $null
$drVpc = $null
$primarySubnet = $null
$drSubnet = $null
$primaryAmi = $null
$drAmi = $null
$identityUp = $false
$platformUp = $false
$workloadUp = $false
$release = '2026.07.1'
$failure = $null
$saved = @{}
$environmentNames = @(
  'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED', 'AWS_PAGER',
  'TF_VAR_run_id', 'TF_VAR_state_bucket', 'TF_VAR_expected_release', 'TF_VAR_primary_subnet_id',
  'TF_VAR_dr_subnet_id', 'TF_VAR_primary_image_id', 'TF_VAR_dr_image_id', 'TF_VAR_localstack_endpoint'
)
foreach ($name in $environmentNames) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }

try {
  try {
    Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null
  } catch {
    throw 'LocalStack is unavailable.'
  }

  $env:AWS_ACCESS_KEY_ID = 'test'
  $env:AWS_SECRET_ACCESS_KEY = 'test'
  $env:AWS_DEFAULT_REGION = 'us-east-1'
  $env:AWS_EC2_METADATA_DISABLED = 'true'
  $env:AWS_PAGER = ''

  $primaryVpc = (Aws 'us-east-1' @('ec2', 'create-vpc', '--cidr-block', '10.150.0.0/16', '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text.Trim()
  $primarySubnet = (Aws 'us-east-1' @('ec2', 'create-subnet', '--vpc-id', $primaryVpc, '--cidr-block', '10.150.1.0/24', '--availability-zone', 'us-east-1a', '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text.Trim()
  $drVpc = (Aws 'us-west-2' @('ec2', 'create-vpc', '--cidr-block', '10.250.0.0/16', '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text.Trim()
  $drSubnet = (Aws 'us-west-2' @('ec2', 'create-subnet', '--vpc-id', $drVpc, '--cidr-block', '10.250.1.0/24', '--availability-zone', 'us-west-2a', '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text.Trim()
  $primaryAmi = (Aws 'us-east-1' @('ec2', 'register-image', '--name', "tfpro-c50-$runId-primary", '--architecture', 'x86_64', '--root-device-name', '/dev/sda1', '--virtualization-type', 'hvm', '--query', 'ImageId', '--output', 'text') -Quiet).Text.Trim()
  $drAmi = (Aws 'us-west-2' @('ec2', 'register-image', '--name', "tfpro-c50-$runId-dr", '--architecture', 'x86_64', '--root-device-name', '/dev/sda1', '--virtualization-type', 'hvm', '--query', 'ImageId', '--output', 'text') -Quiet).Text.Trim()

  $env:TF_VAR_run_id = $runId
  $env:TF_VAR_state_bucket = $stateBucket
  $env:TF_VAR_expected_release = $release
  $env:TF_VAR_primary_subnet_id = $primarySubnet
  $env:TF_VAR_dr_subnet_id = $drSubnet
  $env:TF_VAR_primary_image_id = $primaryAmi
  $env:TF_VAR_dr_image_id = $drAmi
  $env:TF_VAR_localstack_endpoint = $LocalstackEndpoint

  Copy-Clean $identitySource $identityWork
  Copy-Clean $platformSource $platformWork
  Copy-Clean $workloadSource $workloadWork
  Copy-Clean (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $temp 'fixtures')

  Aws 'us-east-1' @('s3api', 'create-bucket', '--bucket', $stateBucket) -Quiet | Out-Null
  $identityBackend = Join-Path $temp 'identity.backend.hcl'
  $platformBackend = Join-Path $temp 'platform.backend.hcl'
  $workloadBackend = Join-Path $temp 'workload.backend.hcl'
  Write-Backend $identityBackend $stateBucket 'identity/terraform.tfstate'
  Write-Backend $platformBackend $stateBucket 'platform/terraform.tfstate'
  Write-Backend $workloadBackend $stateBucket 'workload/terraform.tfstate'

  foreach ($root in @($identityWork, $platformWork, $workloadWork)) { Tf $root @('fmt', '-check', '-recursive') | Out-Null }

  $identityArgs = @('-input=false', '-no-color', "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
  Tf $identityWork @('init', '-input=false', '-no-color', "-backend-config=$identityBackend") | Out-Null
  Tf $identityWork @('validate', '-no-color') | Out-Null
  Exact-Tests $identityWork 'identity.tftest.hcl' 4
  $identityPlan = Join-Path $identityWork 'identity.tfplan'
  Tf $identityWork (@('plan', "-out=$identityPlan") + $identityArgs) | Out-Null
  Assert-Changes (Plan-Json $identityWork $identityPlan) @{
    'aws_iam_role.runtime'                       = 'create'
    'aws_iam_policy.runtime'                     = 'create'
    'aws_iam_role_policy_attachment.runtime'     = 'create'
    'aws_iam_instance_profile.runtime'           = 'create'
  } 'Identity saved plan'
  Tf $identityWork @('apply', '-input=false', '-no-color', $identityPlan) | Out-Null
  $identityUp = $true

  $platformArgsV1 = @(
    '-input=false', '-no-color', "-var=run_id=$runId", "-var=state_bucket=$stateBucket",
    "-var=localstack_endpoint=$LocalstackEndpoint", '-var=manifest_path=../../fixtures/manifest-v1.json'
  )
  Tf $platformWork @('init', '-input=false', '-no-color', "-backend-config=$platformBackend") | Out-Null
  Tf $platformWork @('validate', '-no-color') | Out-Null
  Exact-Tests $platformWork 'platform.tftest.hcl' 7
  $platformPlan = Join-Path $platformWork 'platform-v1.tfplan'
  Tf $platformWork (@('plan', "-out=$platformPlan") + $platformArgsV1) | Out-Null
  Assert-Changes (Plan-Json $platformWork $platformPlan) @{
    'aws_s3_bucket.release'  = 'create'
    'aws_s3_object.bootstrap' = 'create'
  } 'Platform v1 saved plan'
  Tf $platformWork @('apply', '-input=false', '-no-color', $platformPlan) | Out-Null
  $platformUp = $true

  $workloadBase = @(
    '-input=false', '-no-color', "-var=run_id=$runId", "-var=state_bucket=$stateBucket",
    "-var=primary_subnet_id=$primarySubnet", "-var=dr_subnet_id=$drSubnet",
    "-var=primary_image_id=$primaryAmi", "-var=dr_image_id=$drAmi",
    "-var=localstack_endpoint=$LocalstackEndpoint"
  )
  $workloadV1 = $workloadBase + @('-var=expected_release=2026.07.1', '-var=catalog_path=../../fixtures/fleets.json')
  Tf $workloadWork @('init', '-input=false', '-no-color', "-backend-config=$workloadBackend") | Out-Null
  Tf $workloadWork @('validate', '-no-color') | Out-Null
  Exact-Tests $workloadWork 'workload.tftest.hcl' 8
  Write-Host '[unit] identity 4/4, platform 7/7, and workload 8/8 normal Terraform 1.6.6 runs passed.'

  if ($UnitOnly) {
    Tf $platformWork (@('destroy', '-auto-approve') + $platformArgsV1) | Out-Null
    $platformUp = $false
    Tf $identityWork (@('destroy', '-auto-approve') + $identityArgs) | Out-Null
    $identityUp = $false
    Aws 'us-east-1' @('s3', 'rb', "s3://$stateBucket", '--force') -Quiet | Out-Null
    $stateBucket = $null
    Write-Host 'PASS challenge-50 UnitOnly'
    return
  }

  $workloadPlan = Join-Path $workloadWork 'workload-v1.tfplan'
  Tf $workloadWork (@('plan', "-out=$workloadPlan") + $workloadV1) | Out-Null
  Assert-Changes (Plan-Json $workloadWork $workloadPlan) @{
    'module.primary.aws_instance.node["api@primary"]' = 'create'
    'module.dr.aws_instance.node["worker@dr"]'        = 'create'
  } 'Workload v1 saved plan'
  Tf $workloadWork @('apply', '-input=false', '-no-color', $workloadPlan) | Out-Null
  $workloadUp = $true

  $stateKeys = @(((Aws 'us-east-1' @('s3api', 'list-objects-v2', '--bucket', $stateBucket, '--query', 'Contents[].Key', '--output', 'text') -Quiet).Text -split '\s+' | Where-Object { $_ } | Sort-Object))
  if (($stateKeys -join ',') -ne 'identity/terraform.tfstate,platform/terraform.tfstate,workload/terraform.tfstate') {
    throw "Unexpected S3 state keys: $($stateKeys -join ',')"
  }

  Assert-Clean $identityWork $identityArgs 'Identity post-apply plan'
  Assert-Clean $platformWork $platformArgsV1 'Platform post-apply plan'
  Assert-Clean $workloadWork $workloadV1 'Workload post-apply plan'
  $workloadReordered = $workloadBase + @('-var=expected_release=2026.07.1', '-var=catalog_path=../../fixtures/fleets-reordered.json')
  Assert-Clean $workloadWork $workloadReordered 'Reordered workload plan'

  $driftBody = Join-Path $temp 'manual-drift.txt'
  [IO.File]::WriteAllText($driftBody, 'manual drift', [Text.UTF8Encoding]::new($false))
  Aws 'us-east-1' @('s3api', 'put-object', '--bucket', "tfpro-c50-release-$runId", '--key', 'releases/bootstrap.txt', '--body', $driftBody) -Quiet | Out-Null
  $s3DriftPlan = Join-Path $platformWork 's3-drift.tfplan'
  Tf $platformWork (@('plan', "-out=$s3DriftPlan") + $platformArgsV1) | Out-Null
  Assert-Changes (Plan-Json $platformWork $s3DriftPlan) @{'aws_s3_object.bootstrap' = 'update'} 'Platform S3 drift repair'
  Tf $platformWork @('apply', '-input=false', '-no-color', $s3DriftPlan) | Out-Null

  $workloadContractV1 = ((Tf $workloadWork @('output', '-json', 'workload_contract') -Quiet).Text | ConvertFrom-Json)
  $primaryInstanceV1 = $workloadContractV1.primary.instances.PSObject.Properties['api@primary'].Value
  $drInstanceV1 = $workloadContractV1.dr.instances.PSObject.Properties['worker@dr'].Value
  Aws 'us-east-1' @('ec2', 'create-tags', '--resources', $primaryInstanceV1, '--tags', "Key=Name,Value=$runId-tampered") -Quiet | Out-Null
  $ec2DriftPlan = Join-Path $workloadWork 'ec2-drift.tfplan'
  Tf $workloadWork (@('plan', "-out=$ec2DriftPlan") + $workloadV1) | Out-Null
  Assert-Changes (Plan-Json $workloadWork $ec2DriftPlan) @{'module.primary.aws_instance.node["api@primary"]' = 'update'} 'Workload EC2 tag drift repair'
  Tf $workloadWork @('apply', '-input=false', '-no-color', $ec2DriftPlan) | Out-Null

  $platformArgsV2 = @($platformArgsV1 | ForEach-Object {
    if ($_ -eq '-var=manifest_path=../../fixtures/manifest-v1.json') { '-var=manifest_path=../../fixtures/manifest-v2.json' } else { $_ }
  })
  $platformV2Plan = Join-Path $platformWork 'platform-v2.tfplan'
  Tf $platformWork (@('plan', "-out=$platformV2Plan") + $platformArgsV2) | Out-Null
  Assert-Changes (Plan-Json $platformWork $platformV2Plan) @{'aws_s3_object.bootstrap' = 'update'} 'Platform v2 saved plan'
  Tf $platformWork @('apply', '-input=false', '-no-color', $platformV2Plan) | Out-Null
  $release = '2026.07.2'
  $env:TF_VAR_expected_release = $release

  $stale = Tf $workloadWork (@('plan') + $workloadV1) @(0, 1) -Quiet
  if ($stale.Code -ne 1 -or $stale.Text -notmatch 'Remote state or workload catalog contract is invalid') {
    throw 'The stale workload release contract was not rejected.'
  }

  $workloadV2 = $workloadBase + @('-var=expected_release=2026.07.2', '-var=catalog_path=../../fixtures/fleets.json')
  $workloadV2Plan = Join-Path $workloadWork 'workload-v2.tfplan'
  Tf $workloadWork (@('plan', "-out=$workloadV2Plan") + $workloadV2) | Out-Null
  Assert-Changes (Plan-Json $workloadWork $workloadV2Plan) @{
    'module.primary.aws_instance.node["api@primary"]' = 'delete,create'
    'module.dr.aws_instance.node["worker@dr"]'        = 'delete,create'
  } 'Workload v2 saved plan'
  Tf $workloadWork @('apply', '-input=false', '-no-color', $workloadV2Plan) | Out-Null
  $workloadContractV2 = ((Tf $workloadWork @('output', '-json', 'workload_contract') -Quiet).Text | ConvertFrom-Json)
  $primaryInstanceV2 = $workloadContractV2.primary.instances.PSObject.Properties['api@primary'].Value
  $drInstanceV2 = $workloadContractV2.dr.instances.PSObject.Properties['worker@dr'].Value
  if ($primaryInstanceV2 -eq $primaryInstanceV1 -or $drInstanceV2 -eq $drInstanceV1) { throw 'The v2 remote contract did not replace both regional instances.' }

  Assert-Clean $identityWork $identityArgs 'Final identity plan'
  Assert-Clean $platformWork $platformArgsV2 'Final platform plan'
  Assert-Clean $workloadWork $workloadV2 'Final workload plan'

  $workloadDestroy = Join-Path $workloadWork 'workload-destroy.tfplan'
  Tf $workloadWork (@('plan', '-destroy', "-out=$workloadDestroy") + $workloadV2) | Out-Null
  Assert-Changes (Plan-Json $workloadWork $workloadDestroy) @{
    'module.primary.aws_instance.node["api@primary"]' = 'delete'
    'module.dr.aws_instance.node["worker@dr"]'        = 'delete'
  } 'Workload saved destroy'
  Tf $workloadWork @('apply', '-input=false', '-no-color', $workloadDestroy) | Out-Null
  $workloadUp = $false

  $platformDestroy = Join-Path $platformWork 'platform-destroy.tfplan'
  Tf $platformWork (@('plan', '-destroy', "-out=$platformDestroy") + $platformArgsV2) | Out-Null
  Assert-Changes (Plan-Json $platformWork $platformDestroy) @{
    'aws_s3_bucket.release'   = 'delete'
    'aws_s3_object.bootstrap' = 'delete'
  } 'Platform saved destroy'
  Tf $platformWork @('apply', '-input=false', '-no-color', $platformDestroy) | Out-Null
  $platformUp = $false

  $identityDestroy = Join-Path $identityWork 'identity-destroy.tfplan'
  Tf $identityWork (@('plan', '-destroy', "-out=$identityDestroy") + $identityArgs) | Out-Null
  Assert-Changes (Plan-Json $identityWork $identityDestroy) @{
    'aws_iam_role.runtime'                       = 'delete'
    'aws_iam_policy.runtime'                     = 'delete'
    'aws_iam_role_policy_attachment.runtime'     = 'delete'
    'aws_iam_instance_profile.runtime'           = 'delete'
  } 'Identity saved destroy'
  Tf $identityWork @('apply', '-input=false', '-no-color', $identityDestroy) | Out-Null
  $identityUp = $false

  $role = Aws 'us-east-1' @('iam', 'get-role', '--role-name', "tfpro-c50-$runId") @(0, 254) -Quiet
  $profile = Aws 'us-east-1' @('iam', 'get-instance-profile', '--instance-profile-name', "tfpro-c50-$runId") @(0, 254) -Quiet
  if ($role.Code -eq 0 -or $profile.Code -eq 0) { throw 'Managed IAM residue remains.' }
  $bucket = Aws 'us-east-1' @('s3api', 'head-bucket', '--bucket', "tfpro-c50-release-$runId") @(0, 254, 255) -Quiet
  if ($bucket.Code -eq 0) { throw 'Managed release bucket residue remains.' }
  foreach ($region in @('us-east-1', 'us-west-2')) {
    $active = (Aws $region @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text') -Quiet).Text.Trim()
    if ($active) { throw "$region managed EC2 residue remains: $active" }
  }

  Aws 'us-east-1' @('s3', 'rb', "s3://$stateBucket", '--force') -Quiet | Out-Null
  $stateBucket = $null
  Aws 'us-east-1' @('ec2', 'deregister-image', '--image-id', $primaryAmi) -Quiet | Out-Null
  $primaryAmi = $null
  Aws 'us-west-2' @('ec2', 'deregister-image', '--image-id', $drAmi) -Quiet | Out-Null
  $drAmi = $null
  Aws 'us-east-1' @('ec2', 'delete-subnet', '--subnet-id', $primarySubnet) -Quiet | Out-Null
  $primarySubnet = $null
  Aws 'us-west-2' @('ec2', 'delete-subnet', '--subnet-id', $drSubnet) -Quiet | Out-Null
  $drSubnet = $null
  Aws 'us-east-1' @('ec2', 'delete-vpc', '--vpc-id', $primaryVpc) -Quiet | Out-Null
  $primaryVpc = $null
  Aws 'us-west-2' @('ec2', 'delete-vpc', '--vpc-id', $drVpc) -Quiet | Out-Null
  $drVpc = $null

  Write-Host '[e2e] three real S3 states, audited plans, provider routing, reorder, S3/EC2 drift repair, release propagation, ordered saved destroy, and zero residue passed.'
  Write-Host 'PASS challenge-50 (difficulty 95/100, alignment A)'
} catch {
  $failure = $_
} finally {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  if ($workloadUp -and (Test-Path $workloadWork)) {
    & terraform "-chdir=$workloadWork" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" "-var=state_bucket=$stateBucket" "-var=expected_release=$release" "-var=primary_subnet_id=$primarySubnet" "-var=dr_subnet_id=$drSubnet" "-var=primary_image_id=$primaryAmi" "-var=dr_image_id=$drAmi" "-var=localstack_endpoint=$LocalstackEndpoint" '-var=catalog_path=../../fixtures/fleets.json' 2>$null | Out-Null
  }
  if ($platformUp -and (Test-Path $platformWork)) {
    $manifest = if ($release -eq '2026.07.2') { '../../fixtures/manifest-v2.json' } else { '../../fixtures/manifest-v1.json' }
    & terraform "-chdir=$platformWork" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" "-var=state_bucket=$stateBucket" "-var=localstack_endpoint=$LocalstackEndpoint" "-var=manifest_path=$manifest" 2>$null | Out-Null
  }
  if ($identityUp -and (Test-Path $identityWork)) {
    & terraform "-chdir=$identityWork" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" "-var=localstack_endpoint=$LocalstackEndpoint" 2>$null | Out-Null
  }
  if ($stateBucket) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 s3 rb "s3://$stateBucket" --force 2>$null | Out-Null }
  if ($primaryAmi) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 deregister-image --image-id $primaryAmi 2>$null | Out-Null }
  if ($drAmi) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 deregister-image --image-id $drAmi 2>$null | Out-Null }
  if ($primarySubnet) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $primarySubnet 2>$null | Out-Null }
  if ($drSubnet) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-subnet --subnet-id $drSubnet 2>$null | Out-Null }
  if ($primaryVpc) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $primaryVpc 2>$null | Out-Null }
  if ($drVpc) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-vpc --vpc-id $drVpc 2>$null | Out-Null }
  foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
  if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
  $ErrorActionPreference = $old
}
if ($failure) { throw $failure }
