[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot '..\starter'),
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Assert-Endpoint([string]$Endpoint) {
  $uri = $null
  $match = [regex]::Match($Endpoint, '\Ahttp://(?:localhost|127\.0\.0\.1):(?<port>[1-9][0-9]{0,4})\z')
  if ([string]::IsNullOrEmpty($Endpoint) -or $Endpoint.IndexOf([char]13) -ge 0 -or $Endpoint.IndexOf([char]10) -ge 0 -or
      -not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or
      -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or $uri.DnsSafeHost -notin @('localhost', '127.0.0.1') -or
      $uri.PathAndQuery -ne '/' -or -not [string]::IsNullOrEmpty($uri.UserInfo)) {
    throw 'LocalstackEndpoint must be a loopback HTTP root origin with a port from 1 to 65535.'
  }
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  $old = $ErrorActionPreference
  try { $ErrorActionPreference = 'Continue'; $text = @(& $File @Arguments 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE }
  finally { $ErrorActionPreference = $old }
  if ($code -notin $Allowed) { throw "$File $($Arguments -join ' ') exited $code.`n$($text -join [Environment]::NewLine)" }
  return [pscustomobject]@{ ExitCode = $code; Text = ($text -join [Environment]::NewLine) }
}

function Invoke-Aws([string[]]$Arguments, [int[]]$Allowed = @(0)) {
  return Invoke-Native 'aws' (@('--endpoint-url', $LocalstackEndpoint) + $Arguments) $Allowed
}

function Assert-Candidate([string]$Root) {
  $files = @(Get-ChildItem -LiteralPath $Root -File -Filter '*.tf')
  if ($files.Count -ne 4) { throw 'Candidate must contain exactly four root Terraform files.' }
  if (@(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1').Count -ne 0) { throw 'Candidate scripts are out of scope.' }
  $text = ($files | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
  if ($text -match '(?i)TODO|mock_provider|override_|resource\s+"aws_(vpc|subnet)"') { throw 'Candidate is unfinished or manages forbidden fixture infrastructure.' }
  if ($text -notmatch 'required_version\s*=\s*"~>\s*1\.6"' -or $text -notmatch 'version\s*=\s*"~>\s*5\.100\.0"') { throw 'Version constraints differ.' }
  foreach ($pattern in @('access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"', 'ec2\s*=\s*var\.localstack_endpoint', 'sts\s*=\s*var\.localstack_endpoint', 'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true', 'skip_requesting_account_id\s*=\s*true')) {
    if ($text -notmatch $pattern) { throw "Provider contract missing: $pattern" }
  }
  if ([regex]::Matches($text, 'data\s+"aws_subnet"\s+"selected"').Count -ne 1 -or $text -notmatch 'for_each\s*=\s*var\.subnet_tiers') { throw 'Exactly one for_each subnet data block is required.' }
  $resources = @([regex]::Matches($text, 'resource\s+"([^"]+)"\s+"([^"]+)"') | ForEach-Object { "$($_.Groups[1].Value).$($_.Groups[2].Value)" } | Sort-Object)
  if (($resources -join '|') -cne 'aws_security_group.workload|aws_vpc_security_group_ingress_rule.this') { throw 'Managed resource set is not exact.' }
  if ($text -notmatch 'check\s+"rule_contract"' -or $text -notmatch 'for_each\s*=\s*local\.ingress_rules') { throw 'Rule validation and stable graph are required.' }
}

function Read-Plan([string]$Root, [string]$Path) {
  $text = (Invoke-Native 'terraform' @("-chdir=$Root", 'show', '-json', $Path)).Text
  $start = $text.IndexOf('{"format_version"', [StringComparison]::Ordinal)
  if ($start -lt 0) { throw "terraform show did not return plan JSON for $Path." }
  return ($text.Substring($start) | ConvertFrom-Json)
}

function Assert-Plan([object]$Plan, [string[]]$Expected, [string]$Action, [string]$Label) {
  $changed = @($Plan.resource_changes | Where-Object { (@($_.change.actions) -join ',') -ne 'no-op' })
  $actual = @($changed | ForEach-Object { $_.address } | Sort-Object)
  $wanted = @($Expected | Sort-Object)
  if (($actual -join '|') -cne ($wanted -join '|')) { throw "$Label addresses differ: $($actual -join ', ')." }
  foreach ($change in $changed) { if ((@($change.change.actions) -join ',') -cne $Action) { throw "$Label action differs at $($change.address)." } }
}

Assert-Endpoint $LocalstackEndpoint
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw 'terraform is required.' }
if ($null -eq (Get-Command aws -ErrorAction SilentlyContinue)) { throw 'AWS CLI is required.' }
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
Assert-Candidate $candidateRoot
$lab = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$canonical = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'network_factory.tftest.hcl') -Raw
if ($canonical -match 'mock_provider|override_' -or [regex]::Matches($canonical, '(?m)^run\s+"').Count -ne 6) { throw 'Canonical suite must contain exactly six Terraform 1.6 runs.' }

$health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get
foreach ($service in @('ec2', 'sts')) { if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." } }
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED')) { $envBefore[$name] = [Environment]::GetEnvironmentVariable($name) }
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'; $env:AWS_EC2_METADATA_DISABLED = 'true'

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 10)
$networkName = "tfpro-c15-$suffix"
$prefix = "c15-$suffix"
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('tfpro-c15-' + [guid]::NewGuid().ToString('N'))
$work = Join-Path $scratch 'candidate'
$fixtures = Join-Path $scratch 'fixtures'
$vpcId = $null
$subnetIds = @()
$applied = $false
$baseVars = @("-var=network_name=$networkName", "-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint")
$ruleKeys = @('admin|prod|tcp|00022|00022|office', 'api|prod|tcp|00443|00443|office', 'worker|prod|tcp|09100|09100|10.42.0.0/16')
$addresses = @('aws_security_group.workload["admin"]', 'aws_security_group.workload["api"]', 'aws_security_group.workload["worker"]') + @($ruleKeys | ForEach-Object { "aws_vpc_security_group_ingress_rule.this[`"$_`"]" })

try {
  $vpcId = (Invoke-Aws @('ec2', 'create-vpc', '--cidr-block', '10.42.0.0/16', '--query', 'Vpc.VpcId', '--output', 'text')).Text.Trim()
  Invoke-Aws @('ec2', 'create-tags', '--resources', $vpcId, '--tags', "Key=Network,Value=$networkName", 'Key=Name,Value=tfpro-c15-fixture') | Out-Null
  foreach ($spec in @(@{ Tier = 'app'; Cidr = '10.42.1.0/24' }, @{ Tier = 'data'; Cidr = '10.42.2.0/24' })) {
    $id = (Invoke-Aws @('ec2', 'create-subnet', '--vpc-id', $vpcId, '--cidr-block', $spec.Cidr, '--query', 'Subnet.SubnetId', '--output', 'text')).Text.Trim()
    $subnetIds += $id
    Invoke-Aws @('ec2', 'create-tags', '--resources', $id, '--tags', "Key=Network,Value=$networkName", "Key=Tier,Value=$($spec.Tier)") | Out-Null
  }

  New-Item -ItemType Directory -Path $work, $fixtures, (Join-Path $work 'tests') -Force | Out-Null
  Get-ChildItem -LiteralPath $candidateRoot -Force | Copy-Item -Destination $work -Recurse -Force
  Get-ChildItem -LiteralPath (Join-Path $lab 'fixtures') -Force | Copy-Item -Destination $fixtures -Recurse -Force
  [IO.File]::WriteAllText((Join-Path $work 'tests\network_factory.tftest.hcl'), $canonical.Replace('__NETWORK_NAME__', $networkName), [Text.UTF8Encoding]::new($false))
  Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $work) | Out-Null
  Invoke-Native 'terraform' @("-chdir=$work", 'init', '-input=false', '-no-color') | Out-Null
  Invoke-Native 'terraform' @("-chdir=$work", 'validate', '-no-color') | Out-Null
  $tests = Invoke-Native 'terraform' @("-chdir=$work", 'test', '-no-color')
  if ($tests.Text -notmatch 'Success! 6 passed, 0 failed') { throw 'Canonical run count/result mismatch.' }
  Write-Host '[unit] 6 Terraform 1.6 normal plan runs passed against real LocalStack subnet data.'
  if ($UnitOnly) { Write-Host 'PASS challenge-15 UnitOnly'; return }

  $initial = Join-Path $scratch 'initial.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-input=false', "-out=$initial") + $baseVars) | Out-Null
  Assert-Plan (Read-Plan $work $initial) $addresses 'create' 'Initial plan'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', $initial) | Out-Null
  $applied = $true

  $outputs = (Invoke-Native 'terraform' @("-chdir=$work", 'output', '-json')).Text | ConvertFrom-Json
  foreach ($service in @('admin', 'api', 'worker')) {
    $groupId = [string]$outputs.security_group_ids.value.$service
    $remoteRules = (Invoke-Aws @('ec2', 'describe-security-group-rules', '--filters', "Name=group-id,Values=$groupId", '--output', 'json')).Text | ConvertFrom-Json
    $count = @($remoteRules.SecurityGroupRules | Where-Object { -not $_.IsEgress }).Count
    if ($count -ne 1) { throw "$service does not have exactly one managed ingress rule." }
  }

  $reordered = Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-detailed-exitcode', '-input=false') + $baseVars + @("-var=rules_file=$(Join-Path $fixtures 'rules-reordered.csv')")) @(0, 2)
  if ($reordered.ExitCode -ne 0) { throw 'Reordered CSV must produce a clean plan.' }

  $apiKey = 'api|prod|tcp|00443|00443|office'
  $apiRule = [string]$outputs.rule_ids.value.$apiKey
  $apiGroup = [string]$outputs.security_group_ids.value.api
  Invoke-Aws @('ec2', 'revoke-security-group-ingress', '--group-id', $apiGroup, '--security-group-rule-ids', $apiRule) | Out-Null
  $repair = Join-Path $scratch 'repair.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-input=false', "-out=$repair") + $baseVars) | Out-Null
  Assert-Plan (Read-Plan $work $repair) @('aws_vpc_security_group_ingress_rule.this["api|prod|tcp|00443|00443|office"]') 'create' 'Repair plan'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', $repair) | Out-Null
  $clean = Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-detailed-exitcode', '-input=false') + $baseVars) @(0, 2)
  if ($clean.ExitCode -ne 0) { throw 'Post-repair plan is not clean.' }

  $destroy = Join-Path $scratch 'destroy.tfplan'
  Invoke-Native 'terraform' (@("-chdir=$work", 'plan', '-destroy', '-input=false', "-out=$destroy") + $baseVars) | Out-Null
  Assert-Plan (Read-Plan $work $destroy) $addresses 'delete' 'Destroy plan'
  Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-input=false', $destroy) | Out-Null
  $applied = $false

  $remoteGroups = (Invoke-Aws @('ec2', 'describe-security-groups', '--output', 'json')).Text | ConvertFrom-Json
  if (@($remoteGroups.SecurityGroups | Where-Object { $_.GroupName -like "$prefix-*" }).Count -ne 0) { throw 'Managed security groups remain after destroy.' }
  foreach ($id in @($subnetIds)) { Invoke-Aws @('ec2', 'delete-subnet', '--subnet-id', $id) | Out-Null }
  $subnetIds = @()
  Invoke-Aws @('ec2', 'delete-vpc', '--vpc-id', $vpcId) | Out-Null
  $vpcId = $null
  $remainingVpcs = (Invoke-Aws @('ec2', 'describe-vpcs', '--filters', "Name=tag:Network,Values=$networkName", '--query', 'length(Vpcs)', '--output', 'text')).Text.Trim()
  if ($remainingVpcs -ne '0') { throw 'LocalStack network fixture remains after cleanup.' }
  Write-Host 'PASS challenge-15: 6/6 tests, real subnet queries, saved apply, revoke drift repair, clean plan, audited destroy, zero residue.'
}
finally {
  if ($applied -and (Test-Path $work)) { try { Invoke-Native 'terraform' (@("-chdir=$work", 'destroy', '-auto-approve', '-input=false') + $baseVars) @(0, 1) | Out-Null } catch {} }
  foreach ($id in @($subnetIds)) { if ($id) { try { Invoke-Aws @('ec2', 'delete-subnet', '--subnet-id', $id) @(0, 255) | Out-Null } catch {} } }
  if ($vpcId) { try { Invoke-Aws @('ec2', 'delete-vpc', '--vpc-id', $vpcId) @(0, 255) | Out-Null } catch {} }
  foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
  if (Test-Path $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
