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
function Aws([string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) { Native 'aws.exe' (@('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1') + $Arguments) $Allowed -Quiet:$Quiet }
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
function Sha256([string]$Value) {
  $algorithm = [Security.Cryptography.SHA256]::Create()
  try { (($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $algorithm.Dispose() }
}

Assert-Endpoint $LocalstackEndpoint
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if (-not $files.Count -or @($files | Where-Object Extension -ne '.tf').Count) { throw 'Candidate must contain HCL only.' }
$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($text -match '(?i)\b(terraform_data|mock_provider|override_data|override_resource|ignore_changes|shared_credentials|assume_role)\b|AKIA[0-9A-Z]{16}') { throw 'Forbidden workaround, mock, or credential mechanism found.' }
if ($text -match 'nonsensitive\s*\(\s*(?:var\.policy_json|local\.raw|try\s*\(\s*local\.raw\.statements)') { throw 'The entire sensitive input or statement object list must not be declassified.' }
$types = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($types -join ',') -ne 'aws_iam_policy,aws_iam_role,aws_iam_role_policy_attachment,aws_s3_bucket') { throw "Unexpected managed AWS types: $($types -join ',')" }
foreach ($token in @('variable "policy_json"', 'sensitive = true', 'raw_statements = try(local.raw.statements, [])', 'statement_key_sets = try(nonsensitive([', 'for statement in local.raw_statements : keys(statement)', 'for statement in local.raw_statements : {', 'key     = statement.key', 'scope   = statement.scope', 'actions = statement.actions', 'replace(title(statement.key), "-", "")', 'data "aws_caller_identity" "current"', 'data "aws_iam_session_context" "current"', 'data "aws_iam_policy_document" "trust"', 'data "aws_iam_policy_document" "compiled"', 'for_each = local.statement_map', 'secret_digest = sha256(local.raw.secret)', 'force_destroy = true')) {
  if ($text -notmatch [regex]::Escape($token)) { throw "Missing sensitive policy contract token: $token" }
}
if ($text -notmatch 'access_key\s*=\s*"test"' -or $text -notmatch 'secret_key\s*=\s*"test"' -or $text -notmatch 'skip_credentials_validation\s*=\s*true' -or
    $text -notmatch 'skip_metadata_api_check\s*=\s*true' -or $text -notmatch 'skip_requesting_account_id\s*=\s*true' -or $text -notmatch 's3_use_path_style\s*=\s*true') { throw 'Safe LocalStack provider contract missing.' }
$versionText = (Native 'terraform' @('version', '-json') -Quiet).Text; $version = $versionText.Substring($versionText.IndexOf('{')) | ConvertFrom-Json
if ($version.terraform_version -ne '1.6.6') { throw "Terraform 1.6.6 required, found $($version.terraform_version)." }

$runId = 'c54' + ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c54-$runId"; $work = Join-Path $temp 'candidate'; $failure = $null
$policyText = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\fixtures\policy.json'); $policyObject = $policyText | ConvertFrom-Json
$reorderedText = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\fixtures\policy-reordered.json')
$secret = [string]$policyObject.secret; $digest = Sha256 $secret
$oldAccess = $env:AWS_ACCESS_KEY_ID; $oldSecret = $env:AWS_SECRET_ACCESS_KEY; $oldRegion = $env:AWS_DEFAULT_REGION; $oldPolicy = $env:TF_VAR_policy_json
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $env:TF_VAR_policy_json = $policyText
try {
  try { Invoke-WebRequest -UseBasicParsing "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null } catch { throw 'LocalStack is unavailable.' }
  Copy-Clean $candidatePath $work; Copy-Item (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $work 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force (Join-Path $work 'tests') | Out-Null; Copy-Item (Join-Path $PSScriptRoot 'canonical.tftest.hcl') (Join-Path $work 'tests\canonical.tftest.hcl')
  Tf $work @('fmt', '-check', '-recursive') | Out-Null; Tf $work @('init', '-backend=false', '-input=false', '-no-color') | Out-Null; Tf $work @('validate', '-no-color') | Out-Null
  $tests = Tf $work @('test', '-test-directory=tests', '-no-color', "-var=run_id=$runId")
  if ([regex]::Matches($tests.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 8 -or $tests.Text -notmatch '(?m)^Success!\s+8 passed,\s+0 failed\.\s*$') { throw 'Expected exact 8/8 canonical tests.' }
  if ($UnitOnly) { Write-Host 'PASS: Challenge 54 exact 8/8 Terraform 1.6.6 tests.'; return }

  $common = @('-input=false', '-no-color', "-var=run_id=$runId")
  $createPlan = Join-Path $work 'create.tfplan'; $planResult = Tf $work (@('plan', "-out=$createPlan") + $common)
  if ($planResult.Text -match [regex]::Escape($secret)) { throw 'Human-readable plan leaked the raw secret.' }
  $planJson = Plan-Json $work $createPlan
  Assert-Map (Action-Map $planJson) @{
    'aws_s3_bucket.evidence' = 'create'; 'aws_iam_role.workload' = 'create'; 'aws_iam_policy.compiled' = 'create'; 'aws_iam_role_policy_attachment.compiled' = 'create'
  } 'create'
  if ($planJson.planned_values.outputs.policy_receipt.sensitive -ne $true) { throw 'Saved plan lacks the sensitive output marker.' }
  Tf $work @('apply', '-input=false', '-no-color', $createPlan) | Out-Null

  $stateText = Get-Content -Raw -LiteralPath (Join-Path $work 'terraform.tfstate')
  if ($stateText -match [regex]::Escape($secret)) { throw 'Raw secret entered Terraform state.' }
  $outputs = (Tf $work @('output', '-json') -Quiet).Text | ConvertFrom-Json
  $receipt = $outputs.policy_receipt
  if ($receipt.sensitive -ne $true -or $receipt.value.secret_digest -ne $digest -or $receipt.value.issuer_arn -notmatch '^arn:aws:') { throw 'Sensitive digest/session receipt invalid.' }
  $contract = $outputs.ownership_contract.value
  Aws @('s3api', 'head-bucket', '--bucket', $contract.bucket_name) | Out-Null
  Aws @('iam', 'get-role', '--role-name', $contract.role_name) | Out-Null
  $attached = ((Aws @('iam', 'list-attached-role-policies', '--role-name', $contract.role_name, '--query', 'AttachedPolicies[].PolicyArn', '--output', 'text') -Quiet).Text).Trim()
  if ($attached -ne $contract.policy_arn) { throw 'Real IAM attachment contract mismatch.' }
  $defaultVersion = ((Aws @('iam', 'get-policy', '--policy-arn', $contract.policy_arn, '--query', 'Policy.DefaultVersionId', '--output', 'text') -Quiet).Text).Trim()
  $document = (Aws @('iam', 'get-policy-version', '--policy-arn', $contract.policy_arn, '--version-id', $defaultVersion, '--query', 'PolicyVersion.Document', '--output', 'json') -Quiet).Text
  foreach ($action in @('s3:ListBucket', 's3:GetObject', 's3:PutObject')) { if ($document -notmatch [regex]::Escape($action)) { throw "Compiled policy missing $action." } }
  if ($document -match [regex]::Escape($secret)) { throw 'Compiled IAM policy leaked the secret.' }

  $env:TF_VAR_policy_json = $reorderedText
  $reorder = Tf $work (@('plan', '-detailed-exitcode') + $common) @(0, 2) -Quiet; if ($reorder.Code -ne 0) { throw 'Statement/action reorder changed the graph.' }
  $env:TF_VAR_policy_json = $policyText
  Aws @('iam', 'detach-role-policy', '--role-name', $contract.role_name, '--policy-arn', $contract.policy_arn) | Out-Null
  $driftPlan = Join-Path $work 'drift.tfplan'; $drift = Tf $work (@('plan', '-detailed-exitcode', "-out=$driftPlan") + $common) @(0, 2) -Quiet; if ($drift.Code -ne 2) { throw 'Detached policy drift was not detected.' }
  Assert-Map (Action-Map (Plan-Json $work $driftPlan)) @{ 'aws_iam_role_policy_attachment.compiled' = 'create' } 'attachment drift'
  Tf $work @('apply', '-input=false', '-no-color', $driftPlan) | Out-Null; $clean = Tf $work (@('plan', '-detailed-exitcode') + $common) @(0, 2) -Quiet; if ($clean.Code -ne 0) { throw 'Final plan is not clean.' }
  Tf $work (@('destroy', '-auto-approve') + $common) | Out-Null
  $buckets = (Aws @('s3api', 'list-buckets', '--query', "Buckets[?contains(Name, '$runId')].Name", '--output', 'text') -Quiet).Text
  $roles = (Aws @('iam', 'list-roles', '--query', "Roles[?contains(RoleName, '$runId')].RoleName", '--output', 'text') -Quiet).Text
  $policies = (Aws @('iam', 'list-policies', '--scope', 'Local', '--query', "Policies[?contains(PolicyName, '$runId')].PolicyName", '--output', 'text') -Quiet).Text
  if (-not [string]::IsNullOrWhiteSpace($buckets) -or -not [string]::IsNullOrWhiteSpace($roles) -or -not [string]::IsNullOrWhiteSpace($policies)) { throw 'Run-scoped S3/IAM residue remains.' }
  Write-Host 'PASS: Challenge 54 TF1.6.6 + sensitive metadata/CLI/state audit + real IAM/S3 drift repair + zero residue.'
} catch { $failure = $_ } finally {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $env:TF_VAR_policy_json = $policyText
  if (Test-Path (Join-Path $work 'terraform.tfstate')) { & terraform "-chdir=$work" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" 2>$null | Out-Null }
  $env:AWS_ACCESS_KEY_ID = $oldAccess; $env:AWS_SECRET_ACCESS_KEY = $oldSecret; $env:AWS_DEFAULT_REGION = $oldRegion; $env:TF_VAR_policy_json = $oldPolicy
  if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }; $ErrorActionPreference = $old
}
if ($failure) { throw $failure }
