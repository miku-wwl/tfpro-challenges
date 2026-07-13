[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "../starter"),
  [string]$LocalStackEndpoint = "http://localhost:4566"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$challengeRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$candidatePath = (Resolve-Path $Candidate).Path
$script:checks = 0
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("tfpro-c21-" + [guid]::NewGuid().ToString("N"))
$namePrefix = "tfpro-c21-" + ([guid]::NewGuid().ToString("N").Substring(0, 8))
$runId = "c21-" + ([guid]::NewGuid().ToString("N").Substring(0, 16))
$candidateDirectory = $null

function Assert-LoopbackEndpoint {
  param([string]$Endpoint)
  $uri = $null
  if (-not [uri]::TryCreate($Endpoint, [System.UriKind]::Absolute, [ref]$uri)) {
    throw "LocalStackEndpoint must be an absolute URI"
  }
  $endpointHost = $uri.Host.Trim('[', ']').ToLowerInvariant()
  if ($uri.Scheme -notin @("http", "https") -or
    $endpointHost -notin @("localhost", "127.0.0.1", "::1") -or
    -not [string]::IsNullOrEmpty($uri.UserInfo) -or
    $uri.AbsolutePath -ne "/" -or
    -not [string]::IsNullOrEmpty($uri.Query) -or
    -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw "LocalStackEndpoint must be an HTTP(S) loopback root URL"
  }
}

function Remove-HclComments {
  param([string]$Text)
  $builder = [Text.StringBuilder]::new($Text.Length)
  $state = "code"
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $current = $Text[$i]
    $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
    if ($state -eq "code") {
      if ($current -eq '"') { [void]$builder.Append($current); $state = "string" }
      elseif ($current -eq '#') { [void]$builder.Append(' '); $state = "line" }
      elseif ($current -eq '/' -and $next -eq '/') { [void]$builder.Append("  "); $i++; $state = "line" }
      elseif ($current -eq '/' -and $next -eq '*') { [void]$builder.Append("  "); $i++; $state = "block" }
      else { [void]$builder.Append($current) }
    }
    elseif ($state -eq "string") {
      [void]$builder.Append($current)
      if ($current -eq '\' -and $i + 1 -lt $Text.Length) { $i++; [void]$builder.Append($Text[$i]) }
      elseif ($current -eq '"') { $state = "code" }
    }
    elseif ($state -eq "line") {
      if ($current -eq "`n") { [void]$builder.Append($current); $state = "code" }
      else { [void]$builder.Append(' ') }
    }
    else {
      if ($current -eq '*' -and $next -eq '/') { [void]$builder.Append("  "); $i++; $state = "code" }
      elseif ($current -eq "`n") { [void]$builder.Append($current) }
      else { [void]$builder.Append(' ') }
    }
  }
  return $builder.ToString()
}

function Get-HclBlocks {
  param([string]$Text, [string]$HeaderPattern)
  $blocks = [Collections.Generic.List[string]]::new()
  foreach ($match in [regex]::Matches($Text, $HeaderPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
    $open = $Text.IndexOf('{', $match.Index)
    if ($open -lt 0) { continue }
    $depth = 0
    $inString = $false
    for ($i = $open; $i -lt $Text.Length; $i++) {
      $current = $Text[$i]
      if ($inString) {
        if ($current -eq '\') { $i++; continue }
        if ($current -eq '"') { $inString = $false }
        continue
      }
      if ($current -eq '"') { $inString = $true; continue }
      if ($current -eq '{') { $depth++ }
      elseif ($current -eq '}') {
        $depth--
        if ($depth -eq 0) {
          $blocks.Add($Text.Substring($match.Index, $i - $match.Index + 1))
          break
        }
      }
    }
  }
  return @($blocks)
}

Assert-LoopbackEndpoint $LocalStackEndpoint

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
  $script:checks++
  Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Invoke-Terraform {
  param([string]$Directory, [string[]]$Arguments)
  Push-Location $Directory
  try {
    & terraform @Arguments | Out-Host
    $code = $LASTEXITCODE
  }
  finally { Pop-Location }
  if ($code -ne 0) { throw "terraform $($Arguments -join ' ') failed with exit code $code" }
}

function Invoke-TerraformCapture {
  param([string]$Directory, [string[]]$Arguments)
  Push-Location $Directory
  try {
    $lines = @(& terraform @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $code = $LASTEXITCODE
  }
  finally { Pop-Location }
  $captured = $lines -join "`n"
  Write-Host $captured
  if ($code -ne 0) { throw "terraform $($Arguments -join ' ') failed with exit code $code" }
  return $captured
}

function Assert-PlanReportsCheck {
  param([string]$Directory, [string[]]$Arguments, [string]$ExpectedMessage, [string]$Description)
  Push-Location $Directory
  try {
    $lines = @(& terraform @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $code = $LASTEXITCODE
  }
  finally { Pop-Location }
  $captured = $lines -join "`n"
  Assert-True ($code -eq 0 -and $captured.Contains($ExpectedMessage)) $Description
}

function Assert-PlanRejected {
  param([string]$Directory, [string[]]$Arguments, [string]$ExpectedMessage, [string]$Description)
  Push-Location $Directory
  try {
    $lines = @(& terraform @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    $code = $LASTEXITCODE
  }
  finally { Pop-Location }
  $captured = $lines -join "`n"
  Assert-True ($code -ne 0 -and $captured.Contains($ExpectedMessage)) $Description
}

function Invoke-AwsJson {
  param([string[]]$Arguments)
  $raw = (& aws --endpoint-url $LocalStackEndpoint @Arguments --output json --no-cli-pager 2>&1) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "aws $($Arguments -join ' ') failed: $raw" }
  return ($raw | ConvertFrom-Json)
}

function Get-RunResources {
  $rules = @(Invoke-AwsJson @("ec2", "describe-security-group-rules", "--filters", "Name=tag:RunId,Values=$runId") | Select-Object -ExpandProperty SecurityGroupRules)
  $groups = @(Invoke-AwsJson @("ec2", "describe-security-groups", "--filters", "Name=tag:RunId,Values=$runId") | Select-Object -ExpandProperty SecurityGroups)
  $subnets = @(Invoke-AwsJson @("ec2", "describe-subnets", "--filters", "Name=tag:RunId,Values=$runId") | Select-Object -ExpandProperty Subnets)
  $vpcs = @(Invoke-AwsJson @("ec2", "describe-vpcs", "--filters", "Name=tag:RunId,Values=$runId") | Select-Object -ExpandProperty Vpcs)
  return [pscustomobject]@{
    Rules   = $rules
    Groups  = $groups
    Subnets = $subnets
    Vpcs    = $vpcs
  }
}

function Remove-RunResources {
  $resources = Get-RunResources
  foreach ($rule in $resources.Rules) {
    & aws --endpoint-url $LocalStackEndpoint ec2 revoke-security-group-ingress --group-id $rule.GroupId --security-group-rule-ids $rule.SecurityGroupRuleId --no-cli-pager 2>$null | Out-Null
  }
  $resources = Get-RunResources
  foreach ($group in $resources.Groups) {
    & aws --endpoint-url $LocalStackEndpoint ec2 delete-security-group --group-id $group.GroupId --no-cli-pager 2>$null | Out-Null
  }
  $resources = Get-RunResources
  foreach ($subnet in $resources.Subnets) {
    & aws --endpoint-url $LocalStackEndpoint ec2 delete-subnet --subnet-id $subnet.SubnetId --no-cli-pager 2>$null | Out-Null
  }
  $resources = Get-RunResources
  foreach ($vpc in $resources.Vpcs) {
    & aws --endpoint-url $LocalStackEndpoint ec2 delete-vpc --vpc-id $vpc.VpcId --no-cli-pager 2>$null | Out-Null
  }
}

function Invoke-DetailedPlan {
  param([string]$Directory, [string[]]$Arguments)
  Push-Location $Directory
  try {
    & terraform @Arguments | Out-Host
    $code = $LASTEXITCODE
  }
  finally { Pop-Location }
  if ($code -notin @(0, 2)) { throw "terraform plan failed with exit code $code" }
  return $code
}

function Test-LocalStackServices {
  $health = Invoke-RestMethod -Uri "$LocalStackEndpoint/_localstack/health" -TimeoutSec 5
  foreach ($service in @("ec2", "sts")) {
    $property = $health.services.PSObject.Properties[$service]
    Assert-True ($null -ne $property -and $property.Value -in @("available", "running")) "LocalStack $service service is healthy"
  }
}

function Assert-CandidateContract {
  $files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File -Filter "*.tf")
  Assert-True ($files.Count -gt 0) "candidate contains Terraform configuration"
  $configuration = Remove-HclComments (($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n")
  $providerBlocks = @(Get-HclBlocks $configuration '(?m)^[ \t]*provider\s+"aws"\s*\{')
  Assert-True ($providerBlocks.Count -eq 1) "candidate contains exactly one AWS provider block"
  $providerBlock = $providerBlocks[0]
  $providerAssignments = @{
    access_key                  = '"test"'
    secret_key                  = '"test"'
    region                      = 'var\.aws_region'
    skip_credentials_validation = 'true'
    skip_metadata_api_check     = 'true'
    skip_requesting_account_id  = 'true'
    ec2                         = 'var\.localstack_endpoint'
    sts                         = 'var\.localstack_endpoint'
  }
  foreach ($assignment in $providerAssignments.GetEnumerator()) {
    $pattern = '(?m)^\s*' + [regex]::Escape($assignment.Key) + '\s*=\s*' + $assignment.Value + '\s*$'
    Assert-True ([regex]::Matches($providerBlock, $pattern).Count -eq 1) "AWS provider sets $($assignment.Key) exactly and safely"
  }
  Assert-True ([regex]::Matches($configuration, '(?m)^\s*default\s*=\s*"http://localhost:4566"\s*$').Count -eq 1) "LocalStack endpoint defaults exactly to loopback edge"
  Assert-True ($configuration -match 'rule\.environment\s*==\s*var\.environment\s*&&\s*rule\.enabled') "only enabled target-environment rules enter the graph"
  Assert-True ($configuration -match 'rule\.rule_id\s*=>\s*rule') "rule_id is the stable for_each identity"
  Assert-True ($configuration -match 'data\s+"aws_vpc"\s+"managed"' -and $configuration -match 'data\s+"aws_subnet"\s+"managed"' -and $configuration -match 'data\.aws_subnet\.managed\[each\.value\.subnet_key\]\.cidr_block') "rule CIDRs are resolved through VPC/subnet data sources"
  foreach ($checkName in @("unique_rule_ids", "rule_subnets_exist", "valid_rule_ports", "consistent_group_owners")) {
    Assert-True ($configuration -match "check\s+`"$checkName`"") "configuration defines $checkName check"
  }
  Assert-True ($configuration -match 'owners\s*=\s*sort' -and $configuration -match 'owner\s*=>\s*sort') "owner grouping and members are deterministically sorted"
  Assert-True ($configuration -match 'RunId\s*=\s*var\.run_id') "all managed resource families carry the unique RunId cleanup tag"
}

New-Item -ItemType Directory -Path $tempRoot | Out-Null
$oldAccessKey = $env:AWS_ACCESS_KEY_ID
$oldSecretKey = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$vpcId = $null

try {
  Assert-CandidateContract
  Test-LocalStackServices
  Copy-Item (Join-Path $challengeRoot "fixtures") (Join-Path $tempRoot "fixtures") -Recurse -Force

  $candidateDirectory = Join-Path $tempRoot "candidate"
  New-Item -ItemType Directory -Path $candidateDirectory | Out-Null
  Copy-Item (Join-Path $candidatePath "*") $candidateDirectory -Recurse -Force
  New-Item -ItemType Directory -Path (Join-Path $candidateDirectory "tests") -Force | Out-Null
  Copy-Item (Join-Path $PSScriptRoot "contract.tftest.hcl") (Join-Path $candidateDirectory "tests/contract.tftest.hcl") -Force

  Invoke-Terraform $candidateDirectory @("init", "-backend=false", "-input=false")
  $testOutput = Invoke-TerraformCapture $candidateDirectory @("test", "-no-color")
  Assert-True ($testOutput -match '(?m)^Success! 4 passed, 0 failed\.$') "canonical mock test reports exactly 4/4 passed"

  $duplicatePath = (Resolve-Path (Join-Path $tempRoot "fixtures/rules-duplicate-id.csv")).Path
  $invalidRulePath = (Resolve-Path (Join-Path $tempRoot "fixtures/rules-invalid-port-protocol.csv")).Path
  $ownerConflictPath = (Resolve-Path (Join-Path $tempRoot "fixtures/rules-owner-conflict.csv")).Path
  $invalidNetworkPath = (Resolve-Path (Join-Path $tempRoot "fixtures/invalid-network.json")).Path
  $missingRulesPath = Join-Path $tempRoot "fixtures/does-not-exist.csv"
  $behaviorBase = @("plan", "-no-color", "-refresh=false", "-input=false", "-var=name_prefix=$namePrefix", "-var=run_id=$runId", "-var=localstack_endpoint=$LocalStackEndpoint")
  Assert-PlanReportsCheck $candidateDirectory ($behaviorBase + "-var=rules_csv_path=$duplicatePath") "CSV rule_id values must be globally unique" "duplicate rule IDs reach and fail the uniqueness check without a duplicate-key crash"
  Assert-PlanReportsCheck $candidateDirectory ($behaviorBase + "-var=rules_csv_path=$invalidRulePath") "Active rules require tcp/udp and valid ordered ports" "invalid protocol and ports reach the rule-domain check"
  Assert-PlanReportsCheck $candidateDirectory ($behaviorBase + "-var=rules_csv_path=$ownerConflictPath") "All rules in one security group must have the same owner" "conflicting owners reach the group-owner check"
  Assert-PlanRejected $candidateDirectory ($behaviorBase + "-var-file=$invalidNetworkPath") "network 必须包含有效 VPC/subnet CIDR" "invalid complex network input is rejected by variable validation"
  Assert-PlanRejected $candidateDirectory ($behaviorBase + "-var=rules_csv_path=$missingRulesPath") "rules_csv_path 必须指向存在的 CSV 文件" "missing rules path is rejected by variable validation"

  # Tests tear down their mock state; use the same isolated directory for a real LocalStack apply.
  Invoke-Terraform $candidateDirectory @("apply", "-auto-approve", "-input=false", "-var=name_prefix=$namePrefix", "-var=run_id=$runId", "-var=localstack_endpoint=$LocalStackEndpoint")

  $contractRaw = (& terraform "-chdir=$candidateDirectory" output -json topology_contract) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "failed to read topology contract" }
  $contract = $contractRaw | ConvertFrom-Json
  $vpcId = $contract.vpc_id
  Assert-True ($contract.vpc_cidr -eq "10.42.0.0/16" -and $contract.rule_count -eq 5) "real topology reports one VPC and five enabled prod rules"

  $state = @(& terraform "-chdir=$candidateDirectory" state list)
  Assert-True (@($state | Where-Object { $_ -match '^aws_subnet\.this\[' }).Count -eq 3) "state contains three stable subnet instances"
  Assert-True (@($state | Where-Object { $_ -match '^aws_security_group\.this\[' }).Count -eq 3) "state contains three stable security-group instances"
  Assert-True (@($state | Where-Object { $_ -match '^aws_vpc_security_group_ingress_rule\.this\[' }).Count -eq 5) "state contains five rule_id-keyed ingress instances"
  Assert-True (-not ($state -match 'this\["[0-9]+-')) "no ingress state address is based on a CSV row index"

  $groupRaw = (& aws --endpoint-url $LocalStackEndpoint ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpcId" --output json --no-cli-pager) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "failed to inspect LocalStack security groups" }
  $groups = @(($groupRaw | ConvertFrom-Json).SecurityGroups | Where-Object { $_.GroupName -like "$namePrefix-*" })
  $permissionCount = @($groups | ForEach-Object { $_.IpPermissions }).Count
  Assert-True ($groups.Count -eq 3 -and $permissionCount -eq 5) "LocalStack contains three managed groups and five real ingress permissions"

  $cleanExit = Invoke-DetailedPlan $candidateDirectory @("plan", "-detailed-exitcode", "-input=false", "-var=name_prefix=$namePrefix", "-var=run_id=$runId", "-var=localstack_endpoint=$LocalStackEndpoint")
  Assert-True ($cleanExit -eq 0) "canonical CSV produces a clean plan"

  $reorderedPath = (Resolve-Path (Join-Path $tempRoot "fixtures/rules-reordered.csv")).Path
  $reorderedExit = Invoke-DetailedPlan $candidateDirectory @("plan", "-detailed-exitcode", "-input=false", "-var=name_prefix=$namePrefix", "-var=run_id=$runId", "-var=localstack_endpoint=$LocalStackEndpoint", "-var=rules_csv_path=$reorderedPath")
  Assert-True ($reorderedExit -eq 0) "reordered equivalent CSV produces a zero-change plan"

  $ownerRaw = (& terraform "-chdir=$candidateDirectory" output -json rules_by_owner) -join "`n"
  $owners = $ownerRaw | ConvertFrom-Json
  Assert-True (($owners.PSObject.Properties.Name -join ",") -eq "data,edge,platform") "owner grouping exposes deterministic owner keys"
  Assert-True (($owners.platform -join ",") -eq "api-from-web,metrics-from-private") "owner members are stable and sorted"

  Invoke-Terraform $candidateDirectory @("destroy", "-auto-approve", "-input=false", "-var=name_prefix=$namePrefix", "-var=run_id=$runId", "-var=localstack_endpoint=$LocalStackEndpoint")
  & aws --endpoint-url $LocalStackEndpoint ec2 describe-vpcs --vpc-ids $vpcId --output json --no-cli-pager 2>$null | Out-Null
  Assert-True ($LASTEXITCODE -ne 0) "destroy removes the challenge VPC and dependent resources"
  $residue = Get-RunResources
  Assert-True ($residue.Rules.Count -eq 0 -and $residue.Groups.Count -eq 0 -and $residue.Subnets.Count -eq 0 -and $residue.Vpcs.Count -eq 0) "destroy leaves no resource carrying this run's unique RunId tag"

  Write-Host "Challenge 21 passed: 4 canonical runs plus $script:checks contract/lifecycle checks." -ForegroundColor Cyan
}
finally {
  if ($candidateDirectory -and (Test-Path (Join-Path $candidateDirectory "terraform.tfstate"))) {
    $remainingState = @(& terraform "-chdir=$candidateDirectory" state list 2>$null)
    if ($LASTEXITCODE -eq 0 -and $remainingState.Count -gt 0) {
      & terraform "-chdir=$candidateDirectory" destroy -auto-approve -input=false "-var=name_prefix=$namePrefix" "-var=run_id=$runId" "-var=localstack_endpoint=$LocalStackEndpoint" 2>$null | Out-Null
    }
  }
  # Fallback cleanup uses only the unique RunId and respects dependency order.
  $env:AWS_ACCESS_KEY_ID = "test"
  $env:AWS_SECRET_ACCESS_KEY = "test"
  $env:AWS_DEFAULT_REGION = "us-east-1"
  try { Remove-RunResources } catch { }
  $env:AWS_ACCESS_KEY_ID = $oldAccessKey
  $env:AWS_SECRET_ACCESS_KEY = $oldSecretKey
  $env:AWS_DEFAULT_REGION = $oldRegion

  $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
  if ($resolvedTemp.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $resolvedTemp)) {
    Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
  }
}
