[CmdletBinding()]
param(
  [string]$Candidate = '',
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }

function Assert-Endpoint([string]$Value) {
  if ($Value -notmatch '^https?://(?:localhost|127\.0\.0\.1|\[::1\]):[0-9]{1,5}$') {
    throw "Unsafe LocalStack endpoint: $Value"
  }
  $uri = [Uri]$Value
  if (
    $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or
    $uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment -or $uri.UserInfo -or
    $uri.Port -lt 1 -or $uri.Port -gt 65535
  ) {
    throw "Unsafe LocalStack endpoint: $Value"
  }
}

function Native(
  [string]$File,
  [string[]]$Arguments,
  [int[]]$Allowed = @(0),
  [switch]$Quiet
) {
  $oldPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $lines = @(& $File @Arguments 2>&1 | ForEach-Object { "$_" })
  $code = $LASTEXITCODE
  $ErrorActionPreference = $oldPreference
  $joined = $lines -join "`n"
  if (-not $Quiet -and $lines.Count -gt 0) { $lines | Out-Host }
  if ($code -notin $Allowed) {
    throw "$File $($Arguments -join ' ') failed ($code).`n$joined"
  }
  [pscustomobject]@{ Code = $code; Text = $joined }
}

function Tf([string]$Directory, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  Native 'terraform' (@("-chdir=$Directory") + $Arguments) $Allowed -Quiet:$Quiet
}

function Aws([string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  Native 'aws.exe' (@('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1') + $Arguments) $Allowed -Quiet:$Quiet
}

function Probe-Aws([string[]]$Arguments) {
  $oldPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $lines = @(& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 @Arguments 2>&1 | ForEach-Object { "$_" })
  $code = $LASTEXITCODE
  $ErrorActionPreference = $oldPreference
  [pscustomobject]@{
    Code      = $code
    Arguments = ($Arguments -join ' ')
    Text      = (($lines -join "`n").Trim())
  }
}

function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force $Destination | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if (
      $item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup', '.terraform.tfstate.lock.info') -or
      $item.Extension -in @('.tfplan', '.tfstate')
    ) { continue }
    $target = Join-Path $Destination $item.Name
    if ($item.PSIsContainer) { Copy-Clean $item.FullName $target } else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
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

function Exact-Tests([string]$Directory, [string]$TestFile, [int]$Expected) {
  $testDirectory = Join-Path $Directory 'tests'
  New-Item -ItemType Directory -Force $testDirectory | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $TestFile) -Destination (Join-Path $testDirectory $TestFile) -Force
  $result = Tf $Directory @('test', '-test-directory=tests', '-no-color')
  if (
    [regex]::Matches($result.Text, "(?m)^Success!\s+$Expected passed,\s+0 failed\.\s*$").Count -ne 1 -or
    [regex]::Matches($result.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne $Expected
  ) {
    throw "Expected exact $Expected normal Terraform 1.6 runs from $TestFile."
  }
  Remove-Item -LiteralPath $testDirectory -Recurse -Force
}

function Plan-Json([string]$Directory, [string]$PlanPath) {
  ((Tf $Directory @('show', '-json', $PlanPath) -Quiet).Text | ConvertFrom-Json)
}

function Assert-Changes($Document, [hashtable]$Expected, [string]$Label) {
  $actual = @{}
  foreach ($change in @($Document.resource_changes | Where-Object { [string]$_.mode -eq 'managed' })) {
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

function Assert-Instance-Payload(
  [string]$InstanceId,
  [string]$Node,
  [string]$Revision,
  [string]$ArtifactArn,
  [string]$ArtifactDigest
) {
  $encoded = (Aws @(
      'ec2', 'describe-instance-attribute', '--instance-id', $InstanceId, '--attribute', 'userData',
      '--query', 'UserData.Value', '--output', 'text'
    ) -Quiet).Text.Trim()
  if (-not $encoded -or $encoded -eq 'None') { throw "$InstanceId has no runtime user data." }
  try {
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
    $payload = $json | ConvertFrom-Json
  } catch {
    throw "$InstanceId user data is not canonical base64-encoded JSON."
  }
  $fields = @($payload.PSObject.Properties.Name | Sort-Object)
  if (($fields -join ',') -ne 'artifact_arn,artifact_sha256,node,revision,source_state') {
    throw "$InstanceId user data fields are not exact: $($fields -join ',')"
  }
  if (
    [string]$payload.node -ne $Node -or [string]$payload.revision -ne $Revision -or
    [string]$payload.artifact_arn -ne $ArtifactArn -or [string]$payload.artifact_sha256 -ne $ArtifactDigest -or
    [string]$payload.source_state -ne 'publisher/terraform.tfstate'
  ) {
    throw "$InstanceId does not mirror the exact $Node $Revision release payload."
  }
}

Assert-Endpoint $LocalstackEndpoint
$terraformVersion = ((Native 'terraform' @('version', '-json') -Quiet).Text | ConvertFrom-Json).terraform_version
if ($terraformVersion -ne '1.6.6') {
  throw "Terraform 1.6.6 is required; active version is $terraformVersion."
}

$candidate = (Resolve-Path -LiteralPath $Candidate).Path
$publisherSource = Join-Path $candidate 'publisher'
$consumerSource = Join-Path $candidate 'consumer'
if (-not (Test-Path -LiteralPath $publisherSource -PathType Container) -or -not (Test-Path -LiteralPath $consumerSource -PathType Container)) {
  throw 'Candidate must contain publisher and consumer Terraform roots.'
}
$files = @(Get-ChildItem -LiteralPath $candidate -Recurse -File)
if ($files.Count -eq 0 -or @($files | Where-Object Extension -ne '.tf').Count -ne 0) {
  throw 'Candidate roots must contain Terraform HCL only.'
}
$allText = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($allText -match '(?i)\b(TODO|terraform_data|mock_provider|override_data|override_resource|aws_sns_|aws_vpc|aws_subnets|aws_autoscaling_group)\b|ignore_changes|local-exec|remote-exec') {
  throw 'Forbidden unfinished, synthetic, mock, SNS, VPC, ASG, provisioner, or drift-suppression construct found.'
}
if (
  [regex]::Matches($allText, 'required_version\s*=\s*"~> 1\.6"').Count -ne 2 -or
  [regex]::Matches($allText, 'backend\s+"s3"\s*\{\s*\}').Count -ne 2
) {
  throw 'Both roots need Terraform ~> 1.6 and empty partial S3 backends.'
}

$publisherText = (Get-ChildItem -LiteralPath $publisherSource -Filter '*.tf' | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
$consumerText = (Get-ChildItem -LiteralPath $consumerSource -Filter '*.tf' | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
$publisherResources = @([regex]::Matches($publisherText, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$consumerResources = @([regex]::Matches($consumerText, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$consumerData = @([regex]::Matches($consumerText, 'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($publisherResources -join ',') -ne 'aws_s3_bucket,aws_s3_object') {
  throw "Publisher resources are not exact: $($publisherResources -join ',')"
}
if (($consumerResources -join ',') -ne 'aws_instance,aws_launch_template,aws_security_group') {
  throw "Consumer resources are not exact: $($consumerResources -join ',')"
}
if (($consumerData -join ',') -ne 'aws_ami,aws_subnet') {
  throw "Consumer AWS data sources are not exact: $($consumerData -join ',')"
}
if (
  [regex]::Matches($consumerText, 'data\s+"terraform_remote_state"\s+"publisher"').Count -ne 1 -or
  $consumerText -notmatch 'backend\s*=\s*"s3"' -or
  $consumerText -notmatch 'data\.terraform_remote_state\.publisher\.outputs\.artifact_contract'
) {
  throw 'Consumer must use exactly one S3 terraform_remote_state publisher contract.'
}
foreach ($field in @('access_key', 'secret_key', 'use_path_style', 'skip_credentials_validation', 'skip_metadata_api_check', 'skip_requesting_account_id', 'endpoints')) {
  if ($consumerText -notmatch "(?m)^\s*$field\s*=") { throw "Remote-state config misses $field." }
}
if (
  -not $consumerText.Contains('toset(["artifacts", "bucket_arn", "bucket_name", "contract_version", "fingerprint", "producer_run_id", "revision"])') -or
  -not $consumerText.Contains('toset(["arn", "content_sha256", "key", "owner"])') -or
  $consumerText -notmatch 'contract_schema_valid\s*=' -or
  $consumerText -notmatch 'contract_integrity_valid\s*=' -or
  $consumerText -notmatch 'local\.contract\.fingerprint\s*==\s*sha256\(jsonencode\(' -or
  $consumerText -notmatch 'Remote artifact contract schema check failed\.' -or
  $consumerText -notmatch 'Remote artifact contract integrity check failed\.' -or
  $consumerText -notmatch 'release_payloads\s*=\s*\{' -or
  $consumerText -notmatch 'user_data\s*=\s*base64encode\(local\.release_payloads\[each\.key\]\)' -or
  $consumerText -notmatch 'user_data\s*=\s*local\.release_payloads\[each\.key\]' -or
  $consumerText -notmatch 'user_data_replace_on_change\s*=\s*true' -or
  $consumerText -notmatch 'create_before_destroy\s*=\s*true' -or
  $consumerText -notmatch 'replace_triggered_by\s*=\s*\[aws_launch_template\.node\[each\.key\]\]'
) {
  throw 'Launch Template audit specs and EC2 runtimes must share one canonical payload and explicit replacement semantics.'
}
if (
  $consumerText -match '(?m)^\s*launch_template\s*\{' -or
  $consumerText -notmatch 'ami\s*=\s*data\.aws_ami\.selected\.id' -or
  $consumerText -notmatch 'subnet_id\s*=\s*data\.aws_subnet\.selected\.id' -or
  $consumerText -notmatch 'vpc_security_group_ids\s*=\s*\[aws_security_group\.runtime\.id\]'
) {
  throw 'EC2 must use the injected AMI/subnet/security group directly; the Launch Template is an audit spec, not an instance association.'
}
if ([regex]::Matches($allText, 'access_key\s*=\s*"test"').Count -lt 3 -or [regex]::Matches($allText, 'secret_key\s*=\s*"test"').Count -lt 3) {
  throw 'Both providers and remote state must use literal test/test credentials.'
}

$publisherTests = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'publisher.tftest.hcl')
$consumerTests = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'consumer.tftest.hcl')
if (
  ($publisherTests + $consumerTests) -match '(?i)mock_provider|override_' -or
  [regex]::Matches($publisherTests, '(?m)^run\s+"').Count -ne 10 -or
  [regex]::Matches($consumerTests, '(?m)^run\s+"').Count -ne 10
) {
  throw 'Canonical tests must be exact 10+10 normal Terraform 1.6 runs without mocks or overrides.'
}

$suffix = ([Guid]::NewGuid().ToString('N')).Substring(0, 10)
$runId = "c59-$suffix"
$stateBucket = "tfpro-c59-state-$suffix"
$imageName = "tfpro-c59-$runId"
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c59-$suffix"
$candidateWork = Join-Path $temp 'candidate'
$publisherWork = Join-Path $candidateWork 'publisher'
$consumerWork = Join-Path $candidateWork 'consumer'
$publisherInitialized = $false
$consumerInitialized = $false
$publisherUp = $false
$consumerUp = $false
$publisherRevision = '2026.07.1'
$publisherCatalog = 'artifacts-v1.json'
$vpcId = $null
$subnetId = $null
$imageId = $null
$publisherStateBackup = $null
$publisherStateMutationActive = $false
$failure = $null
$successMessage = $null
$savedEnvironment = @{}
foreach ($name in @(
    'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED', 'AWS_PAGER',
    'TF_VAR_run_id', 'TF_VAR_state_bucket', 'TF_VAR_expected_revision', 'TF_VAR_subnet_id', 'TF_VAR_image_name', 'TF_VAR_localstack_endpoint'
  )) {
  $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
}

try {
  :verification do {
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

  $vpcId = (Aws @('ec2', 'create-vpc', '--cidr-block', '10.159.0.0/16', '--tag-specifications', "ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Vpc.VpcId', '--output', 'text') -Quiet).Text.Trim()
  $subnetId = (Aws @('ec2', 'create-subnet', '--vpc-id', $vpcId, '--cidr-block', '10.159.1.0/24', '--availability-zone', 'us-east-1a', '--tag-specifications', "ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]", '--query', 'Subnet.SubnetId', '--output', 'text') -Quiet).Text.Trim()
  $imageId = (Aws @('ec2', 'register-image', '--name', $imageName, '--architecture', 'x86_64', '--root-device-name', '/dev/sda1', '--virtualization-type', 'hvm', '--tag-specifications', "ResourceType=image,Tags=[{Key=RunId,Value=$runId}]", '--query', 'ImageId', '--output', 'text') -Quiet).Text.Trim()

  $env:TF_VAR_run_id = $runId
  $env:TF_VAR_state_bucket = $stateBucket
  $env:TF_VAR_expected_revision = '2026.07.1'
  $env:TF_VAR_subnet_id = $subnetId
  $env:TF_VAR_image_name = $imageName
  $env:TF_VAR_localstack_endpoint = $LocalstackEndpoint

  Copy-Clean $publisherSource $publisherWork
  Copy-Clean $consumerSource $consumerWork
  Copy-Clean (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $temp 'fixtures')

  Aws @('s3api', 'create-bucket', '--bucket', $stateBucket) -Quiet | Out-Null
  $publisherBackend = Join-Path $temp 'publisher.backend.hcl'
  $consumerBackend = Join-Path $temp 'consumer.backend.hcl'
  Write-Backend $publisherBackend $stateBucket 'publisher/terraform.tfstate'
  Write-Backend $consumerBackend $stateBucket 'consumer/terraform.tfstate'

  Tf $publisherWork @('fmt', '-check', '-recursive') | Out-Null
  Tf $consumerWork @('fmt', '-check', '-recursive') | Out-Null
  Tf $publisherWork @('init', '-input=false', '-no-color', "-backend-config=$publisherBackend") | Out-Null
  $publisherInitialized = $true
  Tf $publisherWork @('validate', '-no-color') | Out-Null
  Exact-Tests $publisherWork 'publisher.tftest.hcl' 10

  $publisherBase = @(
    '-input=false', '-no-color',
    "-var=run_id=$runId",
    "-var=localstack_endpoint=$LocalstackEndpoint"
  )
  $publisherV1 = $publisherBase + @('-var=catalog_path=../../fixtures/artifacts-v1.json')
  $publisherV1Plan = Join-Path $publisherWork 'v1.tfplan'
  Tf $publisherWork (@('plan', "-out=$publisherV1Plan") + $publisherV1) | Out-Null
  Assert-Changes (Plan-Json $publisherWork $publisherV1Plan) @{
    'aws_s3_bucket.artifacts'          = 'create'
    'aws_s3_object.artifact["api"]'    = 'create'
    'aws_s3_object.artifact["worker"]' = 'create'
  } 'Publisher v1 saved plan'
  Tf $publisherWork @('apply', '-input=false', '-no-color', $publisherV1Plan) | Out-Null
  $publisherUp = $true

  Tf $consumerWork @('init', '-input=false', '-no-color', "-backend-config=$consumerBackend") | Out-Null
  $consumerInitialized = $true
  Tf $consumerWork @('validate', '-no-color') | Out-Null
  Exact-Tests $consumerWork 'consumer.tftest.hcl' 10
  Write-Host '[unit] publisher 10/10 and consumer 10/10 normal Terraform 1.6.6 runs passed.'

  $consumerV1 = @(
    '-input=false', '-no-color',
    "-var=run_id=$runId",
    "-var=state_bucket=$stateBucket",
    '-var=expected_revision=2026.07.1',
    "-var=subnet_id=$subnetId",
    "-var=image_name=$imageName",
    "-var=localstack_endpoint=$LocalstackEndpoint",
    '-var=manifest_path=../../fixtures/deployments.json'
  )

  if ($UnitOnly) {
    Tf $publisherWork (@('destroy', '-auto-approve') + $publisherV1) | Out-Null
    $publisherUp = $false
    Aws @('s3', 'rb', "s3://$stateBucket", '--force') -Quiet | Out-Null
    $unitStateCheck = Aws @('s3api', 'head-bucket', '--bucket', $stateBucket) @(0, 254, 255) -Quiet
    if ($unitStateCheck.Code -eq 0) { throw 'UnitOnly state bucket residue remains.' }
    $stateBucket = $null
    $successMessage = 'PASS challenge-59 UnitOnly'
    break verification
  }

  $consumerV1Plan = Join-Path $consumerWork 'v1.tfplan'
  Tf $consumerWork (@('plan', "-out=$consumerV1Plan") + $consumerV1) | Out-Null
  Assert-Changes (Plan-Json $consumerWork $consumerV1Plan) @{
    'aws_security_group.runtime'       = 'create'
    'aws_launch_template.node["api"]'  = 'create'
    'aws_launch_template.node["worker"]' = 'create'
    'aws_instance.node["api"]'         = 'create'
    'aws_instance.node["worker"]'      = 'create'
  } 'Consumer v1 saved plan'
  Tf $consumerWork @('apply', '-input=false', '-no-color', $consumerV1Plan) | Out-Null
  $consumerUp = $true
  $contractV1 = ((Tf $consumerWork @('output', '-json', 'deployment_contract') -Quiet).Text | ConvertFrom-Json)
  $oldApiId = [string]$contractV1.instances.api
  $oldWorkerId = [string]$contractV1.instances.worker
  Assert-Instance-Payload $oldApiId 'api' '2026.07.1' "arn:aws:s3:::tfpro-c59-artifacts-$runId/releases/api.txt" ([string]$contractV1.artifact_digests.api)
  Assert-Instance-Payload $oldWorkerId 'worker' '2026.07.1' "arn:aws:s3:::tfpro-c59-artifacts-$runId/releases/worker.txt" ([string]$contractV1.artifact_digests.worker)

  $stateKeys = @(((Aws @('s3api', 'list-objects-v2', '--bucket', $stateBucket, '--query', 'Contents[].Key', '--output', 'text') -Quiet).Text -split '\s+' | Where-Object { $_ } | Sort-Object))
  if (($stateKeys -join ',') -ne 'consumer/terraform.tfstate,publisher/terraform.tfstate') {
    throw "Unexpected remote state keys: $($stateKeys -join ',')"
  }

  $publisherStateBackup = Join-Path $temp 'publisher-state-original.json'
  Aws @('s3api', 'get-object', '--bucket', $stateBucket, '--key', 'publisher/terraform.tfstate', $publisherStateBackup) -Quiet | Out-Null

  $missingFieldPath = Join-Path $temp 'publisher-state-missing-field.json'
  $missingState = Get-Content -Raw -LiteralPath $publisherStateBackup | ConvertFrom-Json
  $missingState.outputs.artifact_contract.value.PSObject.Properties.Remove('bucket_arn')
  $missingState.outputs.artifact_contract.type[1].PSObject.Properties.Remove('bucket_arn')
  [IO.File]::WriteAllText($missingFieldPath, ($missingState | ConvertTo-Json -Depth 100 -Compress), [Text.UTF8Encoding]::new($false))
  $publisherStateMutationActive = $true
  Aws @('s3api', 'put-object', '--bucket', $stateBucket, '--key', 'publisher/terraform.tfstate', '--body', $missingFieldPath) -Quiet | Out-Null
  $missingFieldReadbackPath = Join-Path $temp 'publisher-state-missing-field-readback.json'
  Aws @('s3api', 'get-object', '--bucket', $stateBucket, '--key', 'publisher/terraform.tfstate', $missingFieldReadbackPath) -Quiet | Out-Null
  $missingFieldReadback = Get-Content -Raw -LiteralPath $missingFieldReadbackPath | ConvertFrom-Json
  if (
    $missingFieldReadback.outputs.artifact_contract.value.PSObject.Properties['bucket_arn'] -or
    $missingFieldReadback.outputs.artifact_contract.type[1].PSObject.Properties['bucket_arn']
  ) {
    throw 'The missing-field state mutation was not durably stored in both value and type.'
  }
  $missingFieldPlan = Tf $consumerWork (@('plan') + $consumerV1) @(0, 1) -Quiet
  Aws @('s3api', 'put-object', '--bucket', $stateBucket, '--key', 'publisher/terraform.tfstate', '--body', $publisherStateBackup) -Quiet | Out-Null
  $publisherStateMutationActive = $false
  if ($missingFieldPlan.Code -ne 1 -or $missingFieldPlan.Text -notmatch 'Remote artifact contract schema check failed') {
    throw "A publisher state missing an exact contract field was not rejected by the schema guard (code $($missingFieldPlan.Code)).`n$($missingFieldPlan.Text)"
  }

  $badFingerprintPath = Join-Path $temp 'publisher-state-bad-fingerprint.json'
  $badFingerprintState = Get-Content -Raw -LiteralPath $publisherStateBackup | ConvertFrom-Json
  $badFingerprintState.outputs.artifact_contract.value.fingerprint = ('0' * 64)
  [IO.File]::WriteAllText($badFingerprintPath, ($badFingerprintState | ConvertTo-Json -Depth 100 -Compress), [Text.UTF8Encoding]::new($false))
  $publisherStateMutationActive = $true
  Aws @('s3api', 'put-object', '--bucket', $stateBucket, '--key', 'publisher/terraform.tfstate', '--body', $badFingerprintPath) -Quiet | Out-Null
  $badFingerprintReadbackPath = Join-Path $temp 'publisher-state-bad-fingerprint-readback.json'
  Aws @('s3api', 'get-object', '--bucket', $stateBucket, '--key', 'publisher/terraform.tfstate', $badFingerprintReadbackPath) -Quiet | Out-Null
  $badFingerprintReadback = Get-Content -Raw -LiteralPath $badFingerprintReadbackPath | ConvertFrom-Json
  if ([string]$badFingerprintReadback.outputs.artifact_contract.value.fingerprint -ne ('0' * 64)) {
    throw 'The forged-fingerprint state mutation was not durably stored.'
  }
  $badFingerprintPlan = Tf $consumerWork (@('plan') + $consumerV1) @(0, 1) -Quiet
  Aws @('s3api', 'put-object', '--bucket', $stateBucket, '--key', 'publisher/terraform.tfstate', '--body', $publisherStateBackup) -Quiet | Out-Null
  $publisherStateMutationActive = $false
  if ($badFingerprintPlan.Code -ne 1 -or $badFingerprintPlan.Text -notmatch 'Remote artifact contract integrity check failed') {
    throw "A publisher state with a forged fingerprint was not rejected by the integrity guard (code $($badFingerprintPlan.Code)).`n$($badFingerprintPlan.Text)"
  }

  Assert-Clean $publisherWork $publisherV1 'Publisher v1'
  Assert-Clean $consumerWork $consumerV1 'Consumer v1'
  Assert-Clean $publisherWork ($publisherBase + @('-var=catalog_path=../../fixtures/artifacts-v1-reordered.json')) 'Reordered publisher v1'
  $consumerReordered = @($consumerV1 | ForEach-Object {
      if ($_ -eq '-var=manifest_path=../../fixtures/deployments.json') { '-var=manifest_path=../../fixtures/deployments-reordered.json' } else { $_ }
    })
  Assert-Clean $consumerWork $consumerReordered 'Reordered consumer v1'

  $driftBody = Join-Path $temp 'manual-drift.txt'
  [IO.File]::WriteAllText($driftBody, 'manual drift', [Text.UTF8Encoding]::new($false))
  Aws @('s3api', 'put-object', '--bucket', "tfpro-c59-artifacts-$runId", '--key', 'releases/api.txt', '--body', $driftBody) -Quiet | Out-Null
  $publisherDriftPlan = Join-Path $publisherWork 's3-drift.tfplan'
  $publisherDrift = Tf $publisherWork (@('plan', '-detailed-exitcode', "-out=$publisherDriftPlan") + $publisherV1) @(0, 2) -Quiet
  if ($publisherDrift.Code -ne 2) { throw 'Publisher S3 object drift was not detected.' }
  Assert-Changes (Plan-Json $publisherWork $publisherDriftPlan) @{
    'aws_s3_object.artifact["api"]' = 'update'
  } 'Publisher S3 drift repair'
  Tf $publisherWork @('apply', '-input=false', '-no-color', $publisherDriftPlan) | Out-Null

  Aws @('ec2', 'create-tags', '--resources', $oldApiId, '--tags', "Key=Name,Value=$runId-manual-drift") -Quiet | Out-Null
  $consumerDriftPlan = Join-Path $consumerWork 'ec2-drift.tfplan'
  $consumerDrift = Tf $consumerWork (@('plan', '-detailed-exitcode', "-out=$consumerDriftPlan") + $consumerV1) @(0, 2) -Quiet
  if ($consumerDrift.Code -ne 2) { throw 'Consumer EC2 tag drift was not detected.' }
  Assert-Changes (Plan-Json $consumerWork $consumerDriftPlan) @{
    'aws_instance.node["api"]' = 'update'
  } 'Consumer EC2 drift repair'
  Tf $consumerWork @('apply', '-input=false', '-no-color', $consumerDriftPlan) | Out-Null

  $publisherV2 = $publisherBase + @('-var=catalog_path=../../fixtures/artifacts-v2.json')
  $publisherV2Plan = Join-Path $publisherWork 'v2.tfplan'
  Tf $publisherWork (@('plan', "-out=$publisherV2Plan") + $publisherV2) | Out-Null
  Assert-Changes (Plan-Json $publisherWork $publisherV2Plan) @{
    'aws_s3_object.artifact["api"]'    = 'update'
    'aws_s3_object.artifact["worker"]' = 'update'
  } 'Publisher v2 saved plan'
  Tf $publisherWork @('apply', '-input=false', '-no-color', $publisherV2Plan) | Out-Null
  $publisherRevision = '2026.07.2'
  $publisherCatalog = 'artifacts-v2.json'

  $stale = Tf $consumerWork (@('plan') + $consumerV1) @(0, 1) -Quiet
  if ($stale.Code -ne 1 -or $stale.Text -notmatch 'remote artifact contract') {
    throw 'A consumer pinned to the stale v1 revision was not rejected.'
  }

  $consumerV2 = @($consumerV1 | ForEach-Object {
      if ($_ -eq '-var=expected_revision=2026.07.1') { '-var=expected_revision=2026.07.2' } else { $_ }
    })
  $consumerV2Plan = Join-Path $consumerWork 'v2.tfplan'
  Tf $consumerWork (@('plan', "-out=$consumerV2Plan") + $consumerV2) | Out-Null
  Assert-Changes (Plan-Json $consumerWork $consumerV2Plan) @{
    'aws_launch_template.node["api"]'    = 'update'
    'aws_launch_template.node["worker"]' = 'update'
    'aws_instance.node["api"]'           = 'create,delete'
    'aws_instance.node["worker"]'        = 'create,delete'
  } 'Consumer v2 saved plan'
  Tf $consumerWork @('apply', '-input=false', '-no-color', $consumerV2Plan) | Out-Null
  $contractV2 = ((Tf $consumerWork @('output', '-json', 'deployment_contract') -Quiet).Text | ConvertFrom-Json)
  if ([string]$contractV2.instances.api -eq $oldApiId -or [string]$contractV2.instances.worker -eq $oldWorkerId -or [string]$contractV2.revision -ne '2026.07.2') {
    throw 'The v2 Launch Template contract did not replace both EC2 instances.'
  }
  Assert-Instance-Payload ([string]$contractV2.instances.api) 'api' '2026.07.2' "arn:aws:s3:::tfpro-c59-artifacts-$runId/releases/api.txt" ([string]$contractV2.artifact_digests.api)
  Assert-Instance-Payload ([string]$contractV2.instances.worker) 'worker' '2026.07.2' "arn:aws:s3:::tfpro-c59-artifacts-$runId/releases/worker.txt" ([string]$contractV2.artifact_digests.worker)

  Assert-Clean $publisherWork $publisherV2 'Publisher v2'
  Assert-Clean $consumerWork $consumerV2 'Consumer v2'

  $consumerDestroyPlan = Join-Path $consumerWork 'destroy.tfplan'
  Tf $consumerWork (@('plan', '-destroy', "-out=$consumerDestroyPlan") + $consumerV2) | Out-Null
  Assert-Changes (Plan-Json $consumerWork $consumerDestroyPlan) @{
    'aws_security_group.runtime'         = 'delete'
    'aws_launch_template.node["api"]'    = 'delete'
    'aws_launch_template.node["worker"]' = 'delete'
    'aws_instance.node["api"]'           = 'delete'
    'aws_instance.node["worker"]'        = 'delete'
  } 'Consumer saved destroy'
  Tf $consumerWork @('apply', '-input=false', '-no-color', $consumerDestroyPlan) | Out-Null
  $consumerUp = $false

  $publisherDestroyPlan = Join-Path $publisherWork 'destroy.tfplan'
  Tf $publisherWork (@('plan', '-destroy', "-out=$publisherDestroyPlan") + $publisherV2) | Out-Null
  Assert-Changes (Plan-Json $publisherWork $publisherDestroyPlan) @{
    'aws_s3_bucket.artifacts'           = 'delete'
    'aws_s3_object.artifact["api"]'     = 'delete'
    'aws_s3_object.artifact["worker"]'  = 'delete'
  } 'Publisher saved destroy'
  Tf $publisherWork @('apply', '-input=false', '-no-color', $publisherDestroyPlan) | Out-Null
  $publisherUp = $false

  $artifactBucket = Aws @('s3api', 'head-bucket', '--bucket', "tfpro-c59-artifacts-$runId") @(0, 254, 255) -Quiet
  if ($artifactBucket.Code -eq 0) { throw 'Artifact bucket residue remains.' }
  $activeInstances = (Aws @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text') -Quiet).Text.Trim()
  $launchTemplates = (Aws @('ec2', 'describe-launch-templates', '--filters', "Name=launch-template-name,Values=$runId-api,$runId-worker", '--query', 'LaunchTemplates[].LaunchTemplateId', '--output', 'text') -Quiet).Text.Trim()
  $securityGroups = (Aws @('ec2', 'describe-security-groups', '--filters', "Name=group-name,Values=tfpro-c59-$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text') -Quiet).Text.Trim()
  if ($activeInstances -or $launchTemplates -or $securityGroups) {
    throw 'Consumer EC2, Launch Template, or security-group residue remains.'
  }

  Aws @('s3', 'rb', "s3://$stateBucket", '--force') -Quiet | Out-Null
  $stateBucketCheck = Aws @('s3api', 'head-bucket', '--bucket', $stateBucket) @(0, 254, 255) -Quiet
  if ($stateBucketCheck.Code -eq 0) { throw 'Remote state bucket residue remains.' }
  $stateBucket = $null
  Aws @('ec2', 'deregister-image', '--image-id', $imageId) -Quiet | Out-Null
  $imageCheckResult = Aws @('ec2', 'describe-images', '--image-ids', $imageId, '--query', 'Images[].ImageId', '--output', 'text') @(0, 254, 255) -Quiet
  $imageCheck = $imageCheckResult.Text.Trim()
  if ($imageCheckResult.Code -eq 0 -and $imageCheck -and $imageCheck -ne 'None') { throw "Grader AMI residue remains: $imageCheck" }
  $imageId = $null
  Aws @('ec2', 'delete-subnet', '--subnet-id', $subnetId) -Quiet | Out-Null
  $subnetCheckResult = Aws @('ec2', 'describe-subnets', '--subnet-ids', $subnetId, '--query', 'Subnets[].SubnetId', '--output', 'text') @(0, 254, 255) -Quiet
  $subnetCheck = $subnetCheckResult.Text.Trim()
  if ($subnetCheckResult.Code -eq 0 -and $subnetCheck -and $subnetCheck -ne 'None') { throw "Grader subnet residue remains: $subnetCheck" }
  $subnetId = $null
  Aws @('ec2', 'delete-vpc', '--vpc-id', $vpcId) -Quiet | Out-Null
  $vpcCheckResult = Aws @('ec2', 'describe-vpcs', '--vpc-ids', $vpcId, '--query', 'Vpcs[].VpcId', '--output', 'text') @(0, 254, 255) -Quiet
  $vpcCheck = $vpcCheckResult.Text.Trim()
  if ($vpcCheckResult.Code -eq 0 -and $vpcCheck -and $vpcCheck -ne 'None') { throw "Grader VPC residue remains: $vpcCheck" }
  $vpcId = $null

  $successMessage = "[e2e] two S3 states, missing-field/forged-fingerprint rejection, shared LT/EC2 payload readback, reorder no-op, S3/EC2 drift repair, exact v2 audit-spec propagation, create-before-destroy replacement, reverse saved destroy, and zero residue passed.`nPASS challenge-59 (difficulty 95/100, alignment A)"
  } while ($false)
} catch {
  $failure = $_
} finally {
  $oldPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $cleanupResidue = @()
  $remainingArtifactBucket = ''
  $remainingStateBucket = ''
  $remainingImage = ''
  $stillActive = ''
  $remainingTemplates = ''
  $remainingGroup = ''
  $remainingSubnet = ''
  $remainingVpc = ''

  if ($publisherStateMutationActive -and $stateBucket -and $publisherStateBackup -and (Test-Path -LiteralPath $publisherStateBackup)) {
    & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 s3api put-object --bucket $stateBucket --key 'publisher/terraform.tfstate' --body $publisherStateBackup 2>$null | Out-Null
    $publisherStateMutationActive = $false
  }

  if ($consumerInitialized -and $stateBucket -and (Test-Path -LiteralPath $consumerWork)) {
    $consumerCleanup = @(
      "-chdir=$consumerWork", 'destroy', '-auto-approve', '-input=false', '-no-color',
      "-var=run_id=$runId", "-var=state_bucket=$stateBucket", "-var=expected_revision=$publisherRevision",
      "-var=subnet_id=$subnetId", "-var=image_name=$imageName", "-var=localstack_endpoint=$LocalstackEndpoint",
      '-var=manifest_path=../../fixtures/deployments.json'
    )
    & terraform @consumerCleanup 2>$null | Out-Null
  }
  if ($publisherInitialized -and $stateBucket -and (Test-Path -LiteralPath $publisherWork)) {
    $publisherCleanup = @(
      "-chdir=$publisherWork", 'destroy', '-auto-approve', '-input=false', '-no-color',
      "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint",
      "-var=catalog_path=../../fixtures/$publisherCatalog"
    )
    & terraform @publisherCleanup 2>$null | Out-Null
  }

  if ($runId) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
      & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 s3 rb "s3://tfpro-c59-artifacts-$runId" --force 2>$null | Out-Null
      & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 s3api head-bucket --bucket "tfpro-c59-artifacts-$runId" 2>$null | Out-Null
      if ($LASTEXITCODE -ne 0) { $remainingArtifactBucket = ''; break }
      $remainingArtifactBucket = "tfpro-c59-artifacts-$runId"
      Start-Sleep -Seconds 1
    }
    $remainingInstances = "$(& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-instances --filters "Name=tag:RunId,Values=$runId" 'Name=instance-state-name,Values=pending,running,stopping,stopped' --query 'Reservations[].Instances[].InstanceId' --output text 2>$null)".Trim()
    $instanceIds = @($remainingInstances -split '\s+' | Where-Object { $_ })
    if ($instanceIds.Count -gt 0) {
      & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 terminate-instances --instance-ids $instanceIds 2>$null | Out-Null
      & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 wait instance-terminated --instance-ids $instanceIds 2>$null | Out-Null
      for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $stillActive = "$(& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-instances --instance-ids $instanceIds --filters 'Name=instance-state-name,Values=pending,running,stopping,stopped' --query 'Reservations[].Instances[].InstanceId' --output text 2>$null)".Trim()
        if (-not $stillActive) { break }
        Start-Sleep -Seconds 1
      }
    }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
      foreach ($templateName in @("$runId-api", "$runId-worker")) {
        & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-launch-template --launch-template-name $templateName 2>$null | Out-Null
      }
      $remainingTemplates = "$(& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-launch-templates --filters "Name=launch-template-name,Values=$runId-api,$runId-worker" --query 'LaunchTemplates[].LaunchTemplateId' --output text 2>$null)".Trim()
      if (-not $remainingTemplates) { break }
      Start-Sleep -Seconds 1
    }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
      & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-security-group --group-name "tfpro-c59-$runId" 2>$null | Out-Null
      $remainingGroup = "$(& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-security-groups --filters "Name=group-name,Values=tfpro-c59-$runId" --query 'SecurityGroups[].GroupId' --output text 2>$null)".Trim()
      if (-not $remainingGroup) { break }
      Start-Sleep -Seconds 1
    }
  }
  if ($stateBucket) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
      & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 s3 rb "s3://$stateBucket" --force 2>$null | Out-Null
      & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 s3api head-bucket --bucket $stateBucket 2>$null | Out-Null
      if ($LASTEXITCODE -ne 0) { $remainingStateBucket = ''; break }
      $remainingStateBucket = $stateBucket
      Start-Sleep -Seconds 1
    }
  }
  if ($imageId) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
      & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 deregister-image --image-id $imageId 2>$null | Out-Null
      $remainingImage = "$(& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-images --image-ids $imageId --query 'Images[].ImageId' --output text 2>$null)".Trim()
      if (-not $remainingImage -or $remainingImage -eq 'None') { $remainingImage = ''; break }
      Start-Sleep -Seconds 1
    }
  }
  if ($subnetId) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
      & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $subnetId 2>$null | Out-Null
      $remainingSubnet = "$(& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-subnets --subnet-ids $subnetId --query 'Subnets[].SubnetId' --output text 2>$null)".Trim()
      if (-not $remainingSubnet) { break }
      Start-Sleep -Seconds 1
    }
  }
  if ($vpcId) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
      & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $vpcId 2>$null | Out-Null
      $remainingVpc = "$(& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 describe-vpcs --vpc-ids $vpcId --query 'Vpcs[].VpcId' --output text 2>$null)".Trim()
      if (-not $remainingVpc) { break }
      Start-Sleep -Seconds 1
    }
  }

  $cleanupProbes = @(
    Probe-Aws @('s3api', 'list-buckets', '--query', "Buckets[?contains(Name, '$suffix')].Name", '--output', 'text')
    Probe-Aws @('ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped', '--query', 'Reservations[].Instances[].InstanceId', '--output', 'text')
    Probe-Aws @('ec2', 'describe-launch-templates', '--filters', "Name=launch-template-name,Values=$runId-api,$runId-worker", '--query', 'LaunchTemplates[].LaunchTemplateId', '--output', 'text')
    Probe-Aws @('ec2', 'describe-security-groups', '--filters', "Name=group-name,Values=tfpro-c59-$runId", '--query', 'SecurityGroups[].GroupId', '--output', 'text')
    Probe-Aws @('ec2', 'describe-images', '--owners', 'self', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Images[].ImageId', '--output', 'text')
    Probe-Aws @('ec2', 'describe-subnets', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Subnets[].SubnetId', '--output', 'text')
    Probe-Aws @('ec2', 'describe-vpcs', '--filters', "Name=tag:RunId,Values=$runId", '--query', 'Vpcs[].VpcId', '--output', 'text')
  )
  foreach ($probe in $cleanupProbes) {
    if ($probe.Code -ne 0) {
      $cleanupResidue += "probe_exit=$($probe.Code) [$($probe.Arguments)] $($probe.Text)"
    } elseif (-not [string]::IsNullOrWhiteSpace($probe.Text)) {
      $cleanupResidue += "probe_residue=[$($probe.Arguments)] $($probe.Text)"
    }
  }

  if ($remainingArtifactBucket) { $cleanupResidue += "artifact_bucket=$remainingArtifactBucket" }
  if ($remainingStateBucket) { $cleanupResidue += "state_bucket=$remainingStateBucket" }
  if ($remainingImage) { $cleanupResidue += "ami=$remainingImage" }
  if ($stillActive) { $cleanupResidue += "instances=$stillActive" }
  if ($remainingTemplates) { $cleanupResidue += "launch_templates=$remainingTemplates" }
  if ($remainingGroup) { $cleanupResidue += "security_group=$remainingGroup" }
  if ($remainingSubnet) { $cleanupResidue += "subnet=$remainingSubnet" }
  if ($remainingVpc) { $cleanupResidue += "vpc=$remainingVpc" }
  if ($cleanupResidue.Count -gt 0) {
    $cleanupMessage = "Fallback cleanup residue after retries: $($cleanupResidue -join '; ')"
    if ($failure) {
      $original = if ($failure -is [System.Management.Automation.ErrorRecord]) { $failure.Exception } elseif ($failure -is [Exception]) { $failure } else { $null }
      $failure = if ($original) { [InvalidOperationException]::new("$([string]$failure)`n$cleanupMessage", $original) } else { [InvalidOperationException]::new("$([string]$failure)`n$cleanupMessage") }
    } else {
      $failure = [InvalidOperationException]::new($cleanupMessage)
    }
  }

  foreach ($name in $savedEnvironment.Keys) {
    [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name])
  }
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
  $ErrorActionPreference = $oldPreference
}

if ($failure) { throw $failure }
if ($successMessage) { Write-Host $successMessage }
