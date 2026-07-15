[CmdletBinding()]
param(
  [string]$Candidate = '',
  [string]$LocalstackEndpoint = "http://localhost:4566",
  [switch]$UnitOnly
)

if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-LoopbackOrigin([string]$Endpoint) {
  if ($Endpoint.Contains("`r") -or $Endpoint.Contains("`n") -or
      -not [regex]::IsMatch($Endpoint, '\Ahttp://(?:localhost|127\.0\.0\.1|\[::1\]):([1-9][0-9]{0,4})\z', [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    throw "LocalstackEndpoint must be a loopback HTTP root origin with an explicit port and no path/query/fragment/newline."
  }
  $portMatch = [regex]::Match($Endpoint, ':([0-9]+)\z')
  if (-not $portMatch.Success -or [int]$portMatch.Groups[1].Value -gt 65535) { throw "LocalstackEndpoint port must be in 1..65535." }
  $uri = $null
  if (-not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri)) { throw "LocalstackEndpoint must be absolute." }
  $hostName = $uri.Host.Trim('[', ']').ToLowerInvariant()
  if ($uri.Scheme -ne 'http' -or $hostName -notin @('localhost', '127.0.0.1', '::1') -or
      -not [string]::IsNullOrEmpty($uri.UserInfo) -or $uri.AbsolutePath -ne '/' -or
      -not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw "LocalstackEndpoint origin is unsafe."
  }
}

function Copy-CleanTree([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Where-Object {
    $_.Name -notin @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup', 'tests')
  } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force }
}

function Invoke-Terraform([string]$Directory, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0)) {
  & terraform "-chdir=$Directory" @Arguments | Out-Host
  $code = $LASTEXITCODE
  if ($code -notin $AllowedExitCodes) { throw "terraform $($Arguments -join ' ') failed, exit=$code." }
  return $code
}

function Read-PlanJson([string]$Directory, [string]$PlanPath) {
  $raw = @(& terraform "-chdir=$Directory" show -json $PlanPath 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "terraform show -json failed: $($raw -join "`n")" }
  $text = $raw -join "`n"
  $start = $text.IndexOf('{"format_version"', [StringComparison]::Ordinal)
  if ($start -lt 0) { throw "terraform show -json did not return plan JSON." }
  return ($text.Substring($start) | ConvertFrom-Json)
}

function Invoke-AwsJson([string[]]$Arguments) {
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $raw = @(& aws --endpoint-url $LocalstackEndpoint --region us-east-1 @Arguments --output json 2>&1)
      $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $savedPreference }
    if ($code -eq 0) {
      $text = $raw -join "`n"
      if ([string]::IsNullOrWhiteSpace($text)) { return $null }
      return ($text | ConvertFrom-Json)
    }
    if ($attempt -lt 5) { Start-Sleep -Seconds 1 }
  }
  throw "aws $($Arguments -join ' ') failed after 5 attempts: $($raw -join "`n")"
}

function Get-Strings([object]$Value) {
  if ($null -eq $Value) { return @() }
  if ($Value -is [string]) { return @([string]$Value) }
  return @($Value | ForEach-Object { [string]$_ })
}

function Assert-Tag([object[]]$Tags, [string]$Key, [string]$Value, [string]$Label) {
  if (@($Tags | Where-Object { $_.Key -eq $Key -and $_.Value -eq $Value }).Count -ne 1) {
    throw "$Label lacks exactly one $Key=$Value tag."
  }
}

# This validation intentionally precedes every network, terraform, and docker command.
Assert-LoopbackOrigin $LocalstackEndpoint

if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw "terraform is required." }
$terraformVersion = (& terraform version -json | ConvertFrom-Json).terraform_version
if ($LASTEXITCODE -ne 0 -or $terraformVersion -ne '1.6.6') { throw "Terraform 1.6.6 is required; active version is $terraformVersion." }
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tfFiles = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -Force -File | Where-Object { $_.Name -match '(?i)\.tf$' })
if ($tfFiles.Count -lt 5) { throw "Candidate lacks the required HCL files." }
if (@(Get-ChildItem -LiteralPath $candidatePath -Recurse -Force -File -Filter '*.ps1').Count -ne 0) { throw "Candidate scripts are prohibited." }
foreach ($file in $tfFiles) {
  if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse HCL is forbidden: $($file.FullName)" }
}
$source = ($tfFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
if ($source -match '(?i)\bTODO\b|FIXME|CHANGEME|not implemented') { throw "Candidate still contains a substantive placeholder." }
if ($source -match '(?i)mock_provider|override_|terraform_data|aws_vpc|aws_subnet|aws_sns') { throw "Candidate contains a prohibited construct or AWS type." }
if ($source -notmatch 'required_version\s*=\s*"~>\s*1\.6"' -or $source -notmatch 'version\s*=\s*"~>\s*5\.100"') { throw "Version contract must be Terraform ~> 1.6 / AWS ~> 5.100." }
foreach ($pattern in @(
  'jsondecode\(file\(',
  'data\s+"aws_caller_identity"\s+"current"',
  'data\s+"aws_iam_session_context"\s+"current"',
  'data\s+"aws_iam_policy_document"\s+"trust"',
  'data\s+"aws_iam_policy_document"\s+"permissions"',
  'dynamic\s+"statement"',
  'resource\s+"aws_iam_role"\s+"directory"',
  'resource\s+"aws_iam_policy"\s+"directory"',
  'resource\s+"aws_iam_role_policy_attachment"\s+"directory"',
  'for_each\s*=\s*local\.entries_by_id',
  'sort\(keys\(entry\.statement_groups\)\)',
  'length\(distinct\(',
  'precondition\s*\{'
)) { if ($source -notmatch $pattern) { throw "Implementation contract is missing: $pattern" } }
if ([regex]::Matches($source, 'precondition\s*\{').Count -lt 10) { throw "At least ten independent semantic/output preconditions are required." }
$resourceTypes = @([regex]::Matches($source, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($resourceTypes -join '|') -cne 'aws_iam_policy|aws_iam_role|aws_iam_role_policy_attachment') { throw "Managed AWS type set differs: $($resourceTypes -join ',')." }
$dataTypes = @([regex]::Matches($source, 'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($dataTypes -join '|') -cne 'aws_caller_identity|aws_iam_policy_document|aws_iam_session_context') { throw "AWS data source set differs: $($dataTypes -join ',')." }
if ($source -match '(?m)^\s*count\s*=|ignore_changes\s*=|provisioner\s+"|data\s+"external"|jsonencode\s*\(|local-exec|remote-exec') { throw "count identity, ignore_changes, provisioners, external data, and hand-built JSON policy are forbidden." }
$providerBlocks = @([regex]::Matches($source, 'provider\s+"aws"\s*\{'))
if ($providerBlocks.Count -ne 1) { throw "The root must declare exactly one aws provider." }
foreach ($pattern in @(
  'access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"',
  'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true', 'skip_requesting_account_id\s*=\s*true',
  '(?m)^\s*iam\s*=\s*var\.localstack_endpoint\s*$', '(?m)^\s*sts\s*=\s*var\.localstack_endpoint\s*$'
)) { if ($source -notmatch $pattern) { throw "Provider safety contract is missing: $pattern" } }
if ($source -match '(?m)^\s*(s3|sns|ec2|dynamodb|sqs|lambda|kms)\s*=') { throw "Challenge 43 provider endpoints may only contain iam/sts." }
if ($source -match '(?im)^\s*(profile|token|shared_config_files|shared_credentials_files)\s*=|\bassume_role\s*\{|AKIA[0-9A-Z]{16}') { throw "Alternate credentials and possible real AWS keys are forbidden." }

$suffix = ([Guid]::NewGuid().ToString('N')).Substring(0, 10)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c43-$suffix"
$workDir = Join-Path $tempRoot 'candidate'
$fixtureDir = Join-Path $tempRoot 'fixtures'
$pluginCache = Join-Path ([IO.Path]::GetTempPath()) 'tfpro-plugin-cache'
$runId = "c43-$suffix"
$ids = @('artifact-reader', 'queue-publisher')
$common = @("-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
$baseVars = @('-var=directory_path=../fixtures/permissions.json') + $common
$reorderVars = @('-var=directory_path=../fixtures/permissions-reordered.json') + $common
$updatedVars = @('-var=directory_path=../fixtures/permissions-updated.json') + $common
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$oldCache = $env:TF_PLUGIN_CACHE_DIR
$remoteMutationStarted = $false

try {
  New-Item -ItemType Directory -Force -Path $tempRoot, $pluginCache | Out-Null
  Copy-CleanTree $candidatePath $workDir
  Copy-Item -LiteralPath (Join-Path $labRoot 'fixtures') -Destination $fixtureDir -Recurse -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $workDir 'tests') | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $workDir 'tests\canonical.tftest.hcl') -Force
  $canonicalText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Raw
  if ($canonicalText -match '(?i)mock_provider|override_' -or [regex]::Matches($canonicalText, '(?m)^\s*run\s+"').Count -ne 21) { throw "Canonical suite must contain exactly 21 normal Terraform 1.6 runs." }
  $env:AWS_ACCESS_KEY_ID = 'test'
  $env:AWS_SECRET_ACCESS_KEY = 'test'
  $env:AWS_DEFAULT_REGION = 'us-east-1'
  $env:TF_PLUGIN_CACHE_DIR = $pluginCache

  Invoke-Terraform $workDir @('fmt', '-check', '-recursive', '-no-color')
  Invoke-Terraform $workDir @('init', '-backend=false', '-input=false', '-no-color')
  Invoke-Terraform $workDir @('validate', '-no-color')
  $testOutput = @(& terraform "-chdir=$workDir" test -test-directory=tests -no-color 2>&1)
  $testCode = $LASTEXITCODE
  $testOutput | Out-Host
  $testText = $testOutput -join "`n"
  if ($testCode -ne 0 -or [regex]::Matches($testText, '(?m)^Success!\s+21 passed,\s+0 failed\.\s*$').Count -ne 1 -or
      [regex]::Matches($testText, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 21) {
    throw "Canonical tests must pass exactly 21/21 runs."
  }
  if ($UnitOnly) { Write-Host 'PASS: Challenge 43 static contract, fmt/init/validate, and 21/21 normal runs passed (UnitOnly).'; return }

  try { $health = Invoke-RestMethod -UseBasicParsing -Uri "$LocalstackEndpoint/_localstack/health" -TimeoutSec 5 }
  catch { throw "LocalStack health endpoint is unavailable: $LocalstackEndpoint" }
  foreach ($service in @('iam', 'sts')) {
    if ($health.services.$service -notin @('available', 'running')) { throw "LocalStack $service is not running." }
  }

  Remove-Item -LiteralPath (Join-Path $workDir 'tests') -Recurse -Force
  $createPlan = Join-Path $workDir 'create.tfplan'
  Invoke-Terraform $workDir (@('plan', "-out=$createPlan", '-input=false', '-no-color') + $baseVars)
  $createJson = Read-PlanJson $workDir $createPlan
  $createChanges = @($createJson.resource_changes | Where-Object { $_.mode -eq 'managed' })
  $expectedCreate = @(
    'aws_iam_policy.directory["artifact-reader"]', 'aws_iam_policy.directory["queue-publisher"]',
    'aws_iam_role.directory["artifact-reader"]', 'aws_iam_role.directory["queue-publisher"]',
    'aws_iam_role_policy_attachment.directory["artifact-reader"]', 'aws_iam_role_policy_attachment.directory["queue-publisher"]'
  ) | Sort-Object
  $actualCreate = @($createChanges | ForEach-Object { [string]$_.address } | Sort-Object)
  if (($actualCreate -join ',') -ne ($expectedCreate -join ',')) { throw "Initial saved-plan graph is not exact: $($actualCreate -join ', ')" }
  if (@($createChanges | Where-Object { (@($_.change.actions) -join ',') -ne 'create' }).Count -ne 0) { throw "Every initial managed action must be create." }
  $remoteMutationStarted = $true
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $createPlan)

  $directory = ((@(& terraform "-chdir=$workDir" output -json directory_contract) -join "`n") | ConvertFrom-Json)
  $iamContract = ((@(& terraform "-chdir=$workDir" output -json iam_contract) -join "`n") | ConvertFrom-Json)
  $identity = ((@(& terraform "-chdir=$workDir" output -json identity_contract) -join "`n") | ConvertFrom-Json)
  if (($directory.entry_ids -join ',') -ne 'artifact-reader,queue-publisher' -or $identity.account_id -ne '000000000000' -or
      -not ([string]$identity.issuer_arn).StartsWith('arn:aws:iam::000000000000:')) { throw "Terraform IAM/STS output contract is wrong." }
  $caller = Invoke-AwsJson @('sts', 'get-caller-identity')
  if ($caller.Account -ne '000000000000' -or $caller.Arn -ne $identity.caller_arn) { throw "Remote STS identity does not match Terraform evidence." }

  foreach ($id in $ids) {
    $entry = $directory.entries.$id
    $managed = $iamContract.$id
    $expectedRole = "$runId-$id-role"
    $expectedPolicy = "$runId-$id-policy"
    if ($managed.role_name -ne $expectedRole -or $managed.policy_name -ne $expectedPolicy) { throw "$id stable IAM names are wrong." }
    $roleResponse = Invoke-AwsJson @('iam', 'get-role', '--role-name', $expectedRole)
    Assert-Tag @($roleResponse.Role.Tags) 'RunId' $runId "role $id"
    Assert-Tag @($roleResponse.Role.Tags) 'EntryId' $id "role $id"
    Assert-Tag @($roleResponse.Role.Tags) 'Owner' $entry.owner "role $id"
    $trustStatements = @($roleResponse.Role.AssumeRolePolicyDocument.Statement)
    if ($trustStatements.Count -ne 1 -or (@(Get-Strings $trustStatements[0].Action) | Sort-Object) -join ',' -ne 'sts:AssumeRole') { throw "$id trust action is wrong." }
    $actualPrincipals = @(Get-Strings $trustStatements[0].Principal.Service | Sort-Object)
    if (($actualPrincipals -join ',') -ne (@($entry.trust_services | Sort-Object) -join ',')) { throw "$id trust principals are not canonical." }

    $policyResponse = Invoke-AwsJson @('iam', 'get-policy', '--policy-arn', $managed.policy_arn)
    Assert-Tag @($policyResponse.Policy.Tags) 'RunId' $runId "policy $id"
    Assert-Tag @($policyResponse.Policy.Tags) 'EntryId' $id "policy $id"
    $version = Invoke-AwsJson @('iam', 'get-policy-version', '--policy-arn', $managed.policy_arn, '--version-id', $policyResponse.Policy.DefaultVersionId)
    $remoteStatements = @($version.PolicyVersion.Document.Statement)
    if ($remoteStatements.Count -ne @($entry.statements).Count) { throw "$id policy statement count is wrong." }
    foreach ($statement in @($entry.statements)) {
      $remote = @($remoteStatements | Where-Object { $_.Sid -eq $statement.sid })
      if ($remote.Count -ne 1 -or $remote[0].Effect -ne $statement.effect -or
          (@(Get-Strings $remote[0].Action | Sort-Object) -join ',') -ne (@($statement.actions | Sort-Object) -join ',') -or
          (@(Get-Strings $remote[0].Resource | Sort-Object) -join ',') -ne (@($statement.resources | Sort-Object) -join ',')) {
        throw "$id/$($statement.sid) remote policy semantics are wrong."
      }
    }
    $attached = Invoke-AwsJson @('iam', 'list-attached-role-policies', '--role-name', $expectedRole)
    if (@($attached.AttachedPolicies).Count -ne 1 -or $attached.AttachedPolicies[0].PolicyArn -ne $managed.policy_arn) { throw "$id attachment is wrong." }
  }

  $reorderCode = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $reorderVars) @(0, 2)
  if ($reorderCode -ne 0) { throw "Reordering JSON entries/lists/keys must produce no changes." }

  $upgradePlan = Join-Path $workDir 'upgrade.tfplan'
  $upgradeCode = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', "-out=$upgradePlan", '-input=false', '-no-color') + $updatedVars) @(0, 2)
  if ($upgradeCode -ne 2) { throw "The permission update must produce an in-place policy change." }
  $upgradeJson = Read-PlanJson $workDir $upgradePlan
  $upgradeChanges = @($upgradeJson.resource_changes | Where-Object { $_.mode -eq 'managed' -and (@($_.change.actions) -join ',') -ne 'no-op' })
  if ($upgradeChanges.Count -ne 1 -or $upgradeChanges[0].address -ne 'aws_iam_policy.directory["artifact-reader"]' -or
      (@($upgradeChanges[0].change.actions) -join ',') -ne 'update') { throw "Upgrade must update exactly artifact-reader policy in place." }
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $upgradePlan)
  $readerPolicy = $iamContract.'artifact-reader'.policy_arn
  $readerMeta = Invoke-AwsJson @('iam', 'get-policy', '--policy-arn', $readerPolicy)
  $readerVersion = Invoke-AwsJson @('iam', 'get-policy-version', '--policy-arn', $readerPolicy, '--version-id', $readerMeta.Policy.DefaultVersionId)
  $readStatement = @($readerVersion.PolicyVersion.Document.Statement | Where-Object { $_.Sid -eq 'ReadArtifacts' })
  if ($readStatement.Count -ne 1 -or (@(Get-Strings $readStatement[0].Action | Sort-Object) -join ',') -ne 's3:GetObject,s3:GetObjectVersion') { throw "Updated policy was not published remotely." }

  $queueRole = "$runId-queue-publisher-role"
  $queuePolicy = $iamContract.'queue-publisher'.policy_arn
  [void](Invoke-AwsJson @('iam', 'detach-role-policy', '--role-name', $queueRole, '--policy-arn', $queuePolicy))
  $driftPlan = Join-Path $workDir 'drift.tfplan'
  $driftCode = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', "-out=$driftPlan", '-input=false', '-no-color') + $updatedVars) @(0, 2)
  if ($driftCode -ne 2) { throw "Attachment drift must be detected." }
  $driftJson = Read-PlanJson $workDir $driftPlan
  $driftChanges = @($driftJson.resource_changes | Where-Object { $_.mode -eq 'managed' -and (@($_.change.actions) -join ',') -ne 'no-op' })
  if ($driftChanges.Count -ne 1 -or $driftChanges[0].address -ne 'aws_iam_role_policy_attachment.directory["queue-publisher"]' -or
      (@($driftChanges[0].change.actions) -join ',') -ne 'create') { throw "Drift plan must recreate exactly queue-publisher attachment." }
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $driftPlan)
  $restored = Invoke-AwsJson @('iam', 'list-attached-role-policies', '--role-name', $queueRole)
  if (@($restored.AttachedPolicies | Where-Object { $_.PolicyArn -eq $queuePolicy }).Count -ne 1) { throw "Attachment drift was not restored remotely." }
  $cleanCode = Invoke-Terraform $workDir (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $updatedVars) @(0, 2)
  if ($cleanCode -ne 0) { throw "Plan must be clean after drift recovery." }

  $destroyPlan = Join-Path $workDir 'destroy.tfplan'
  Invoke-Terraform $workDir (@('plan', '-destroy', "-out=$destroyPlan", '-input=false', '-no-color') + $updatedVars)
  $destroyJson = Read-PlanJson $workDir $destroyPlan
  $destroyChanges = @($destroyJson.resource_changes | Where-Object { $_.mode -eq 'managed' })
  if ($destroyChanges.Count -ne 6 -or @($destroyChanges | Where-Object { (@($_.change.actions) -join ',') -ne 'delete' }).Count -ne 0) { throw "Saved destroy plan must contain exactly six deletes." }
  Invoke-Terraform $workDir @('apply', '-input=false', '-no-color', $destroyPlan)
  $rolesLeft = Invoke-AwsJson @('iam', 'list-roles')
  $policiesLeft = Invoke-AwsJson @('iam', 'list-policies', '--scope', 'Local')
  if (@($rolesLeft.Roles | Where-Object { $_.RoleName -like "$runId-*" }).Count -ne 0 -or
      @($policiesLeft.Policies | Where-Object { $_.PolicyName -like "$runId-*" }).Count -ne 0) { throw "IAM residue remains after destroy." }
  $remoteMutationStarted = $false
  Write-Host 'PASS: Challenge 43 passed 21/21 tests, saved create, IAM/STS remote semantics, reorder, one-policy upgrade, attachment drift recovery, clean/saved destroy, and zero-residue checks.'
}
finally {
  $cleanupFailure = $null
  if ($remoteMutationStarted) {
    foreach ($id in $ids) {
      $roleName = "$runId-$id-role"
      $policyName = "$runId-$id-policy"
      $policyArn = "arn:aws:iam::000000000000:policy/$policyName"
      try { [void](Invoke-AwsJson @('iam', 'detach-role-policy', '--role-name', $roleName, '--policy-arn', $policyArn)) } catch { }
      try { [void](Invoke-AwsJson @('iam', 'delete-role', '--role-name', $roleName)) } catch { }
      try {
        $versions = Invoke-AwsJson @('iam', 'list-policy-versions', '--policy-arn', $policyArn)
        foreach ($version in @($versions.Versions | Where-Object { -not $_.IsDefaultVersion })) {
          try { [void](Invoke-AwsJson @('iam', 'delete-policy-version', '--policy-arn', $policyArn, '--version-id', $version.VersionId)) } catch { }
        }
      } catch { }
      try { [void](Invoke-AwsJson @('iam', 'delete-policy', '--policy-arn', $policyArn)) } catch { }
    }
    try {
      $rolesLeft = Invoke-AwsJson @('iam', 'list-roles')
      $policiesLeft = Invoke-AwsJson @('iam', 'list-policies', '--scope', 'Local')
      if (@($rolesLeft.Roles | Where-Object { $_.RoleName -like "$runId-*" }).Count -ne 0 -or
          @($policiesLeft.Policies | Where-Object { $_.PolicyName -like "$runId-*" }).Count -ne 0) { $cleanupFailure = "This run still has IAM residue." }
    } catch { $cleanupFailure = $_.Exception.Message }
  }
  $env:AWS_ACCESS_KEY_ID = $oldAccess
  $env:AWS_SECRET_ACCESS_KEY = $oldSecret
  $env:AWS_DEFAULT_REGION = $oldRegion
  $env:TF_PLUGIN_CACHE_DIR = $oldCache
  if (Test-Path $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
  if ($null -ne $cleanupFailure) { throw "Challenge 43 finally cleanup failed: $cleanupFailure" }
}
