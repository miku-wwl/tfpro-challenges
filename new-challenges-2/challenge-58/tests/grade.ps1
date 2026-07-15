[CmdletBinding()]
param(
  [string]$Candidate = '',
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)

if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Endpoint([string]$Endpoint) {
  if ([string]::IsNullOrWhiteSpace($Endpoint) -or $Endpoint.Contains("`r") -or $Endpoint.Contains("`n")) { throw 'LocalstackEndpoint must be a single-line loopback HTTP root origin.' }
  $match = [regex]::Match($Endpoint, '\Ahttp://(?:localhost|127\.0\.0\.1|\[::1\]):(?<port>[1-9][0-9]{0,4})\z')
  $uri = $null
  if (-not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or -not [string]::IsNullOrEmpty($uri.UserInfo) -or $uri.PathAndQuery -ne '/') {
    throw 'LocalstackEndpoint must be an explicit loopback HTTP root origin with a valid port.'
  }
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $lines = @(& $File @Arguments 2>&1); $code = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
  $value = $lines -join [Environment]::NewLine
  if ($code -notin $Allowed) { throw "$File $($Arguments -join ' ') exited $code.`n$value" }
  return [pscustomobject]@{ ExitCode = $code; Text = $value }
}

function Invoke-Terraform([string]$Root, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  return Invoke-Native 'terraform' (@("-chdir=$Root") + $Arguments) $Allowed
}

function Invoke-Aws([string[]]$Arguments, [int[]]$Allowed = @(0)) {
  return Invoke-Native 'aws' (@('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1') + $Arguments) $Allowed
}

function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if ($item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') -or $item.Extension -eq '.tfplan') { continue }
    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Destination $item.Name) -Recurse -Force
  }
}

function Read-Plan([string]$Root, [string]$Path) {
  $text = (Invoke-Terraform $Root @('show', '-json', $Path)).Text
  $start = $text.IndexOf('{"format_version"', [StringComparison]::Ordinal)
  if ($start -lt 0) { throw "terraform show did not return plan JSON for $Path." }
  return ($text.Substring($start) | ConvertFrom-Json)
}

function Get-ActionMap([object]$Plan) {
  $map = @{}
  foreach ($change in @($Plan.resource_changes | Where-Object { $_.mode -eq 'managed' })) {
    $action = @($change.change.actions) -join ','
    if ($action -notin @('no-op', 'read')) { $map[$change.address] = $action }
  }
  return $map
}

function Assert-ExactMap([hashtable]$Actual, [hashtable]$Expected, [string]$Label) {
  if ($Actual.Count -ne $Expected.Count) { throw "$Label action count differs: actual=$($Actual.Count), expected=$($Expected.Count)." }
  foreach ($address in $Expected.Keys) {
    if (-not $Actual.ContainsKey($address) -or $Actual[$address] -ne $Expected[$address]) { throw "$Label action differs at ${address}: $($Actual[$address])." }
  }
}

function Get-Strings([object]$Value) {
  if ($null -eq $Value) { return @() }
  if ($Value -is [string]) { return @([string]$Value) }
  return @($Value | ForEach-Object { [string]$_ })
}

function Assert-Tag([object[]]$Tags, [string]$Key, [string]$Value, [string]$Label) {
  if (@($Tags | Where-Object { $_.Key -eq $Key -and $_.Value -eq $Value }).Count -ne 1) { throw "$Label lacks exactly one $Key=$Value tag." }
}

function Assert-Candidate([string]$Root) {
  $files = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File)
  if ($files.Count -ne 11 -or @($files | Where-Object { $_.Extension -ne '.tf' }).Count -ne 0) { throw 'Candidate must contain exactly eleven Terraform HCL files.' }
  $text = ($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
  if ($text -match '(?i)\bTODO\b|FIXME|CHANGEME|mock_provider|override_|terraform_data|ignore_changes|local-exec|remote-exec|resource\s+"aws_(?!iam_role"|iam_policy"|iam_role_policy_attachment")') {
    throw 'Candidate is unfinished or contains a prohibited workaround or AWS resource.'
  }
  $resources = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $data = @([regex]::Matches($text, 'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if (($resources -join '|') -cne 'aws_iam_policy|aws_iam_role|aws_iam_role_policy_attachment' -or [regex]::Matches($text, 'resource\s+"aws_').Count -ne 3) { throw "Managed resource contract differs: $($resources -join ',')." }
  if (($data -join '|') -cne 'aws_iam_policy_document' -or [regex]::Matches($text, 'data\s+"aws_iam_policy_document"').Count -ne 2) { throw "Data source contract differs: $($data -join ',')." }
  if ([regex]::Matches($text, '(?m)^\s*import\s*\{').Count -ne 6 -or [regex]::Matches($text, '(?m)^\s*moved\s*\{').Count -ne 6) { throw 'Exactly six import blocks and six moved blocks are required.' }
  if ($text -match '(?i)terraform\s+import|terraform\s+state\s+mv') { throw 'CLI import and state mv instructions are prohibited in candidate HCL.' }
  foreach ($index in 0, 1) {
    foreach ($type in @('aws_iam_role', 'aws_iam_policy', 'aws_iam_role_policy_attachment')) {
      if ($text -notmatch [regex]::Escape("from = $type.legacy[$index]")) { throw "Moved source is missing: $type.legacy[$index]" }
    }
  }
  foreach ($name in @('api', 'worker')) {
    foreach ($type in @('aws_iam_role.this', 'aws_iam_policy.this', 'aws_iam_role_policy_attachment.this')) {
      if ($text -notmatch [regex]::Escape("module.identity[`"$name`"].$type")) { throw "Final address is missing: $name/$type" }
    }
  }
  foreach ($pattern in @(
      'required_version\s*=\s*"~>\s*1\.6\.0"',
      'version\s*=\s*"~>\s*5\.100\.0"',
      'for_each\s*=\s*local\.compiled_identities',
      'access_key\s*=\s*"test"',
      'secret_key\s*=\s*"test"',
      'skip_credentials_validation\s*=\s*true',
      'skip_metadata_api_check\s*=\s*true',
      'skip_requesting_account_id\s*=\s*true',
      '(?m)^\s*iam\s*=\s*var\.localstack_endpoint\s*$',
      '(?m)^\s*sts\s*=\s*var\.localstack_endpoint\s*$'
    )) {
    if ($text -notmatch $pattern) { throw "Candidate contract is missing: $pattern" }
  }
  if ($text -match '(?m)^\s*(?:s3|ec2|sns|sqs|dynamodb|kms|lambda)\s*=') { throw 'Provider contains an out-of-scope endpoint.' }
}

function Remove-RunResidue([string]$RunId) {
  try {
    $roles = ((Invoke-Aws @('iam', 'list-roles', '--output', 'json')).Text | ConvertFrom-Json).Roles
    $policies = ((Invoke-Aws @('iam', 'list-policies', '--scope', 'Local', '--output', 'json')).Text | ConvertFrom-Json).Policies
    foreach ($role in @($roles | Where-Object { $_.RoleName -like "$RunId-*" })) {
      $attached = ((Invoke-Aws @('iam', 'list-attached-role-policies', '--role-name', $role.RoleName, '--output', 'json')).Text | ConvertFrom-Json).AttachedPolicies
      foreach ($policy in @($attached)) { try { Invoke-Aws @('iam', 'detach-role-policy', '--role-name', $role.RoleName, '--policy-arn', $policy.PolicyArn) @(0, 1) | Out-Null } catch {} }
      try { Invoke-Aws @('iam', 'delete-role', '--role-name', $role.RoleName) @(0, 1) | Out-Null } catch {}
    }
    foreach ($policy in @($policies | Where-Object { $_.PolicyName -like "$RunId-*" })) {
      $entities = ((Invoke-Aws @('iam', 'list-entities-for-policy', '--policy-arn', $policy.Arn, '--output', 'json')).Text | ConvertFrom-Json).PolicyRoles
      foreach ($entity in @($entities)) { try { Invoke-Aws @('iam', 'detach-role-policy', '--role-name', $entity.RoleName, '--policy-arn', $policy.Arn) @(0, 1) | Out-Null } catch {} }
      $versions = ((Invoke-Aws @('iam', 'list-policy-versions', '--policy-arn', $policy.Arn, '--output', 'json')).Text | ConvertFrom-Json).Versions
      foreach ($version in @($versions | Where-Object { -not $_.IsDefaultVersion })) { try { Invoke-Aws @('iam', 'delete-policy-version', '--policy-arn', $policy.Arn, '--version-id', $version.VersionId) @(0, 1) | Out-Null } catch {} }
      try { Invoke-Aws @('iam', 'delete-policy', '--policy-arn', $policy.Arn) @(0, 1) | Out-Null } catch {}
    }
  }
  catch {}
}

# Endpoint validation intentionally precedes filesystem resolution and every external command.
Assert-Endpoint $LocalstackEndpoint
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
Assert-Candidate $candidateRoot
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw 'terraform is required.' }
if ($null -eq (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI is required.' }
$terraformVersion = (Invoke-Native 'terraform' @('version', '-json')).Text | ConvertFrom-Json
if ($terraformVersion.terraform_version -ne '1.6.6') { throw "Terraform 1.6.6 is required; got $($terraformVersion.terraform_version)." }

$labRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$canonical = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Raw
if ($canonical -match '(?i)mock_provider|override_' -or [regex]::Matches($canonical, '(?m)^\s*run\s+"').Count -ne 11) { throw 'Canonical suite must contain exactly eleven normal Terraform 1.6 runs.' }

$runId = 'c58-' + [guid]::NewGuid().ToString('N').Substring(0, 10)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c58-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $tempRoot 'candidate'
$fixtures = Join-Path $tempRoot 'fixtures'
$legacy = Join-Path $fixtures 'legacy'
$vars = @("-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
$v1 = $vars + @('-var=catalog_path=../fixtures/identities-v1.json')
$v1Reordered = $vars + @('-var=catalog_path=../fixtures/identities-v1-reordered.json')
$v2 = $vars + @('-var=catalog_path=../fixtures/identities-v2.json')
$addresses = @()
foreach ($name in @('api', 'worker')) {
  foreach ($resource in @('aws_iam_policy.this', 'aws_iam_role.this', 'aws_iam_role_policy_attachment.this')) { $addresses += "module.identity[`"$name`"].$resource" }
}
$legacyApplied = $false
$candidateOwns = $false
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED')) { $envBefore[$name] = [Environment]::GetEnvironmentVariable($name) }
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $env:AWS_EC2_METADATA_DISABLED = 'true'

try {
  Copy-Clean $candidateRoot $work
  Copy-Clean (Join-Path $labRoot 'fixtures') $fixtures
  New-Item -ItemType Directory -Path (Join-Path $work 'tests') -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $work 'tests\canonical.tftest.hcl') -Force

  $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get -TimeoutSec 5
  foreach ($service in @('iam', 'sts')) { if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." } }

  Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $work) | Out-Null
  Invoke-Terraform $legacy @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Invoke-Terraform $legacy (@('apply', '-auto-approve', '-input=false', '-no-color') + $vars) | Out-Null
  $legacyApplied = $true
  Invoke-Terraform $work @('init', '-backend=false', '-input=false', '-no-color') | Out-Null
  Invoke-Terraform $work @('validate', '-no-color') | Out-Null
  $tests = Invoke-Terraform $work @('test', '-test-directory=tests', '-no-color', "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
  if ([regex]::Matches($tests.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 11 -or $tests.Text -notmatch '(?m)^Success!\s+11 passed,\s+0 failed\.\s*$') {
    throw "Expected exact 11/11 normal Terraform tests.`n$($tests.Text)"
  }
  Write-Host '[unit] real legacy IAM fixture plus 11/11 normal Terraform import-plan tests passed.'
  if ($UnitOnly) {
    Invoke-Terraform $legacy (@('destroy', '-auto-approve', '-input=false', '-no-color') + $vars) | Out-Null
    $legacyApplied = $false
    Remove-RunResidue $runId
    Write-Host 'PASS challenge-58 UnitOnly'
    return
  }

  Remove-Item -LiteralPath (Join-Path $work 'tests') -Recurse -Force
  foreach ($address in @('aws_iam_role_policy_attachment.legacy[1]', 'aws_iam_policy.legacy[1]', 'aws_iam_role.legacy[1]')) {
    Invoke-Terraform $legacy @('state', 'rm', $address) | Out-Null
  }
  Copy-Item -LiteralPath (Join-Path $legacy 'terraform.tfstate') -Destination (Join-Path $work 'terraform.tfstate') -Force
  $legacyApplied = $false
  $candidateOwns = $true

  $initialPlan = Join-Path $tempRoot 'takeover.tfplan'
  Invoke-Terraform $work (@('plan', '-input=false', '-no-color', "-out=$initialPlan") + $v1) | Out-Null
  $initial = Read-Plan $work $initialPlan
  $managedChanges = @($initial.resource_changes | Where-Object { $_.mode -eq 'managed' })
  if ($managedChanges.Count -ne 6 -or (Get-ActionMap $initial).Count -ne 0) { throw 'Takeover must contain six managed no-op changes and no mutation actions.' }
  $legacyTypes = @{ role = 'aws_iam_role'; policy = 'aws_iam_policy'; attachment = 'aws_iam_role_policy_attachment' }
  $finalTypes = @{ role = 'aws_iam_role.this'; policy = 'aws_iam_policy.this'; attachment = 'aws_iam_role_policy_attachment.this' }
  $workerImportIds = @{
    role       = "$runId-worker-role"
    policy     = "arn:aws:iam::000000000000:policy/$runId-worker-policy"
    attachment = "$runId-worker-role/arn:aws:iam::000000000000:policy/$runId-worker-policy"
  }
  foreach ($kind in @('role', 'policy', 'attachment')) {
    $apiAddress = "module.identity[`"api`"].$($finalTypes[$kind])"
    $apiChange = @($managedChanges | Where-Object { $_.address -eq $apiAddress })
    if ($apiChange.Count -ne 1 -or $apiChange[0].previous_address -ne "$($legacyTypes[$kind]).legacy[0]" -or (@($apiChange[0].change.actions) -join ',') -ne 'no-op') {
      throw "API $kind did not perform the exact no-op legacy move."
    }
    $workerAddress = "module.identity[`"worker`"].$($finalTypes[$kind])"
    $workerChange = @($managedChanges | Where-Object { $_.address -eq $workerAddress })
    $importing = if ($workerChange.Count -eq 1) { $workerChange[0].change.PSObject.Properties['importing'] } else { $null }
    if ($workerChange.Count -ne 1 -or (@($workerChange[0].change.actions) -join ',') -ne 'no-op' -or $null -eq $importing -or [string]$importing.Value.id -ne $workerImportIds[$kind]) {
      throw "Worker $kind did not perform the exact declarative import."
    }
  }
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $initialPlan) | Out-Null

  $stateAddresses = @((Invoke-Terraform $work @('state', 'list')).Text -split '\r?\n' | Where-Object { $_ -match 'aws_iam_(?:role|policy|role_policy_attachment)\.this$' })
  if ($stateAddresses.Count -ne 6 -or @($addresses | Where-Object { $_ -notin $stateAddresses }).Count -ne 0) { throw 'Final managed state address contract differs.' }
  $v1Contract = (Invoke-Terraform $work @('output', '-json', 'managed_contract')).Text | ConvertFrom-Json
  foreach ($name in @('api', 'worker')) {
    $entry = $v1Contract.$name
    $role = ((Invoke-Aws @('iam', 'get-role', '--role-name', $entry.role_name, '--output', 'json')).Text | ConvertFrom-Json).Role
    Assert-Tag @($role.Tags) 'RunId' $runId "$name role"
    Assert-Tag @($role.Tags) 'Identity' $name "$name role"
    $attached = ((Invoke-Aws @('iam', 'list-attached-role-policies', '--role-name', $entry.role_name, '--output', 'json')).Text | ConvertFrom-Json).AttachedPolicies
    if (@($attached | Where-Object { $_.PolicyArn -eq $entry.policy_arn }).Count -ne 1) { throw "$name attachment is missing." }
    $meta = ((Invoke-Aws @('iam', 'get-policy', '--policy-arn', $entry.policy_arn, '--output', 'json')).Text | ConvertFrom-Json).Policy
    Assert-Tag @($meta.Tags) 'Owner' $(if ($name -eq 'api') { 'platform' } else { 'delivery' }) "$name policy"
    $version = ((Invoke-Aws @('iam', 'get-policy-version', '--policy-arn', $entry.policy_arn, '--version-id', $meta.DefaultVersionId, '--output', 'json')).Text | ConvertFrom-Json).PolicyVersion
    if ((@(Get-Strings $version.Document.Statement.Action | Sort-Object) -join ',') -cne 's3:GetObject') { throw "$name V1 policy actions differ." }
  }

  $reorder = Invoke-Terraform $work (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $v1Reordered) @(0, 2)
  if ($reorder.ExitCode -ne 0) { throw "Catalog reorder changed the imported graph.`n$($reorder.Text)" }

  $v2Plan = Join-Path $tempRoot 'v2.tfplan'
  Invoke-Terraform $work (@('plan', '-input=false', '-no-color', "-out=$v2Plan") + $v2) | Out-Null
  Assert-ExactMap (Get-ActionMap (Read-Plan $work $v2Plan)) @{ 'module.identity["api"].aws_iam_policy.this' = 'update' } 'V2 policy rollout'
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $v2Plan) | Out-Null
  $v2Contract = (Invoke-Terraform $work @('output', '-json', 'managed_contract')).Text | ConvertFrom-Json
  foreach ($name in @('api', 'worker')) {
    foreach ($field in @('role_arn', 'policy_arn', 'attachment_id')) { if ([string]$v1Contract.$name.$field -cne [string]$v2Contract.$name.$field) { throw "$name $field changed during policy rollout." } }
  }
  $apiMeta = ((Invoke-Aws @('iam', 'get-policy', '--policy-arn', $v2Contract.api.policy_arn, '--output', 'json')).Text | ConvertFrom-Json).Policy
  $apiVersion = ((Invoke-Aws @('iam', 'get-policy-version', '--policy-arn', $v2Contract.api.policy_arn, '--version-id', $apiMeta.DefaultVersionId, '--output', 'json')).Text | ConvertFrom-Json).PolicyVersion
  if ((@(Get-Strings $apiVersion.Document.Statement.Action | Sort-Object) -join ',') -cne 's3:GetObject,s3:GetObjectVersion') { throw 'API V2 policy actions differ.' }

  Invoke-Aws @('iam', 'detach-role-policy', '--role-name', $v2Contract.worker.role_name, '--policy-arn', $v2Contract.worker.policy_arn) | Out-Null
  $repairPlan = Join-Path $tempRoot 'repair.tfplan'
  Invoke-Terraform $work (@('plan', '-input=false', '-no-color', "-out=$repairPlan") + $v2) | Out-Null
  Assert-ExactMap (Get-ActionMap (Read-Plan $work $repairPlan)) @{ 'module.identity["worker"].aws_iam_role_policy_attachment.this' = 'create' } 'Attachment drift repair'
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $repairPlan) | Out-Null
  $clean = Invoke-Terraform $work (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $v2) @(0, 2)
  if ($clean.ExitCode -ne 0) { throw "Post-repair plan is not clean.`n$($clean.Text)" }

  $destroyPlan = Join-Path $tempRoot 'destroy.tfplan'
  Invoke-Terraform $work (@('plan', '-destroy', '-input=false', '-no-color', "-out=$destroyPlan") + $v2) | Out-Null
  $deletes = @{}; foreach ($address in $addresses) { $deletes[$address] = 'delete' }
  Assert-ExactMap (Get-ActionMap (Read-Plan $work $destroyPlan)) $deletes 'Destroy plan'
  Invoke-Terraform $work @('apply', '-input=false', '-no-color', $destroyPlan) | Out-Null
  $candidateOwns = $false
  $managedAfter = @((Invoke-Terraform $work @('state', 'list')).Text -split '\r?\n' | Where-Object { $_ -match 'aws_iam_(?:role|policy|role_policy_attachment)\.this$' })
  if ($managedAfter.Count -ne 0) { throw 'Managed state is not empty after destroy.' }

  $rolesAfter = ((Invoke-Aws @('iam', 'list-roles', '--output', 'json')).Text | ConvertFrom-Json).Roles
  $policiesAfter = ((Invoke-Aws @('iam', 'list-policies', '--scope', 'Local', '--output', 'json')).Text | ConvertFrom-Json).Policies
  if (@($rolesAfter | Where-Object { $_.RoleName -like "$runId-*" }).Count -ne 0 -or @($policiesAfter | Where-Object { $_.PolicyName -like "$runId-*" }).Count -ne 0) { throw 'Challenge 58 IAM residue remains.' }
  Write-Host 'PASS challenge-58: 11/11 tests, three no-op moves, three declarative imports, policy rollout, attachment drift repair, saved destroy, zero residue.'
}
finally {
  if ($candidateOwns -and (Test-Path -LiteralPath $work)) { try { Invoke-Terraform $work (@('destroy', '-auto-approve', '-input=false', '-no-color') + $v2) @(0, 1) | Out-Null } catch {} }
  if ($legacyApplied -and (Test-Path -LiteralPath $legacy)) { try { Invoke-Terraform $legacy (@('destroy', '-auto-approve', '-input=false', '-no-color') + $vars) @(0, 1) | Out-Null } catch {} }
  Remove-RunResidue $runId
  foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
