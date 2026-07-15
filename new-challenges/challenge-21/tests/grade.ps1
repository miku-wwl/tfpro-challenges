[CmdletBinding()]
param(
    [string]$Candidate = (Join-Path $PSScriptRoot "../starter"),
    [string]$LocalstackEndpoint = "http://localhost:4566",
    [switch]$UnitOnly
)

$ErrorActionPreference = "Stop"

function Assert-LoopbackEndpoint {
    param([string]$Endpoint)
    $uri = $null
    if (-not [uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri)) {
        throw "LocalstackEndpoint must be an absolute URI."
    }
    $hostName = $uri.Host.Trim("[", "]").ToLowerInvariant()
    if ($uri.Scheme -notin @("http", "https") -or
        $hostName -notin @("localhost", "127.0.0.1", "::1") -or
        $uri.IsDefaultPort -or $uri.UserInfo -or $uri.AbsolutePath -ne "/" -or $uri.Query -or $uri.Fragment) {
        throw "LocalstackEndpoint must be a loopback root origin with an explicit port."
    }
}

Assert-LoopbackEndpoint $LocalstackEndpoint

function Invoke-Native {
    param([string]$File, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $lines = @(& $File @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = $lines -join [Environment]::NewLine
    if ($code -notin $AllowedExitCodes) {
        throw "$File $($Arguments -join ' ') failed with exit $code.$([Environment]::NewLine)$text"
    }
    return [pscustomobject]@{ ExitCode = $code; Text = $text }
}

function Invoke-Aws {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    return Invoke-Native "aws" (@("--endpoint-url", $LocalstackEndpoint) + $Arguments + @("--no-cli-pager")) $AllowedExitCodes
}

function Copy-CleanTree {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in @(".terraform", ".terraform.lock.hcl", "terraform.tfstate", "terraform.tfstate.backup", ".terraform.tfstate.lock.info") -or
            $item.Extension -eq ".tfplan") {
            continue
        }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) { Copy-CleanTree $item.FullName $target }
        else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
    }
}

function Get-PlanChanges {
    param([string]$WorkRoot, [string]$PlanPath)
    $shown = Invoke-Native "terraform" @("-chdir=$WorkRoot", "show", "-json", $PlanPath)
    $json = $shown.Text | ConvertFrom-Json
    if ($null -eq $json.resource_changes) { return @() }
    return @($json.resource_changes | Where-Object { (@($_.change.actions) -join ",") -ne "no-op" })
}

function New-NetworkFixture {
    param([string]$RunId)
    $tag = "ResourceType=vpc,Tags=[{Key=Challenge,Value=21},{Key=RunId,Value=$RunId}]"
    $vpcJson = (Invoke-Aws @("ec2", "create-vpc", "--cidr-block", "10.42.0.0/16", "--tag-specifications", $tag, "--output", "json")).Text | ConvertFrom-Json
    $vpcId = [string]$vpcJson.Vpc.VpcId

    $definitions = [ordered]@{
        "public-a"  = @{ Cidr = "10.42.10.0/24"; Az = "us-east-1a" }
        "private-a" = @{ Cidr = "10.42.20.0/24"; Az = "us-east-1b" }
        "data-a"    = @{ Cidr = "10.42.30.0/24"; Az = "us-east-1c" }
    }
    $subnets = [ordered]@{}
    foreach ($key in $definitions.Keys) {
        $subnetTag = "ResourceType=subnet,Tags=[{Key=Challenge,Value=21},{Key=RunId,Value=$RunId},{Key=LogicalKey,Value=$key}]"
        $result = (Invoke-Aws @("ec2", "create-subnet", "--vpc-id", $vpcId, "--cidr-block", $definitions[$key].Cidr,
            "--availability-zone", $definitions[$key].Az, "--tag-specifications", $subnetTag, "--output", "json")).Text | ConvertFrom-Json
        $subnets[$key] = [string]$result.Subnet.SubnetId
    }
    return [pscustomobject]@{ VpcId = $vpcId; Subnets = $subnets }
}

function Remove-NetworkFixture {
    param($Fixture)
    if ($null -eq $Fixture) { return }
    foreach ($subnetId in @($Fixture.Subnets.Values)) {
        Invoke-Aws @("ec2", "delete-subnet", "--subnet-id", $subnetId) @(0, 255) | Out-Null
    }
    Invoke-Aws @("ec2", "delete-vpc", "--vpc-id", $Fixture.VpcId) @(0, 255) | Out-Null
}

$challengeRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
$fixtureRoot = Join-Path $challengeRoot "fixtures"

if (@(Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter "*.ps1").Count -ne 0) {
    throw "Candidate work must contain Terraform HCL only."
}
$tfFiles = @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter "*.tf")
$allTf = ($tfFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join [Environment]::NewLine
if ($allTf -match "(?i)\bTODO\b|not implemented|incomplete") {
    throw "Candidate contains an unfinished marker."
}
if ($allTf -match 'resource\s+"aws_(vpc|subnet)"|data\s+"aws_vpc"|terraform_data') {
    throw "Candidate must consume the existing network and cannot manage out-of-list VPC/subnet resources."
}
$resourceTypes = @([regex]::Matches($allTf, '(?m)^\s*resource\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($resourceTypes -join "|") -cne "aws_security_group|aws_vpc_security_group_ingress_rule") {
    throw "Managed types must be exactly security group and VPC ingress rule."
}
if (([regex]::Matches($allTf, 'data\s+"aws_subnet"\s+"managed"')).Count -ne 1) {
    throw "Candidate must query existing subnets with the official aws_subnet data source."
}
foreach ($required in @('access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"',
        'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true',
        'skip_requesting_account_id\s*=\s*true', 'ec2\s*=\s*var\.localstack_endpoint',
        'sts\s*=\s*var\.localstack_endpoint')) {
    if ($allTf -notmatch $required) { throw "Provider safety contract is incomplete." }
}
if ($allTf -match '(?m)^\s*(s3|iam|sns|dynamodb)\s*=\s*var\.localstack_endpoint') {
    throw "Provider endpoints must be exactly ec2 and sts."
}
if ($allTf -notmatch 'precondition\s*\{' -or $allTf -notmatch 'for_each\s*=\s*local\.deployable_rules') {
    throw "Stable graph and blocking contract preconditions are required."
}

$testFile = Join-Path $PSScriptRoot "contract.tftest.hcl"
$testText = [IO.File]::ReadAllText($testFile)
if ($testText -match "(?i)mock_provider|override_(resource|data|module)" -or
    ([regex]::Matches($testText, '(?m)^run\s+"')).Count -ne 10) {
    throw "Canonical suite must contain 10 Terraform 1.6 runs and no mocks or overrides."
}

$health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + "/_localstack/health") -Method Get
foreach ($service in @("ec2", "sts")) {
    if ($null -eq $health.services.$service -or [string]$health.services.$service -notmatch "available|running") {
        throw "LocalStack service $service is unavailable."
    }
}

$tempBase = [IO.Path]::GetTempPath()
$tempRoot = Join-Path $tempBase ("tfpro-c21-grade-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $tempRoot "candidate"
$pluginCache = Join-Path $tempRoot "plugin-cache"
$suffix = [guid]::NewGuid().ToString("N").Substring(0, 10)
$runId = "c21-$suffix"
$network = $null
$terraformInitialized = $false
$envBefore = @{}
foreach ($name in @("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_DEFAULT_REGION", "AWS_EC2_METADATA_DISABLED", "TF_PLUGIN_CACHE_DIR")) {
    $envBefore[$name] = [Environment]::GetEnvironmentVariable($name)
}

try {
    $env:AWS_ACCESS_KEY_ID = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION = "us-east-1"
    $env:AWS_EC2_METADATA_DISABLED = "true"

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $pluginCache -Force | Out-Null
    $env:TF_PLUGIN_CACHE_DIR = $pluginCache
    Copy-CleanTree $candidateRoot $workRoot
    Copy-CleanTree $fixtureRoot (Join-Path $tempRoot "fixtures")
    New-Item -ItemType Directory -Path (Join-Path $workRoot "tests") -Force | Out-Null
    Copy-Item -LiteralPath $testFile -Destination (Join-Path $workRoot "tests/contract.tftest.hcl") -Force

    Invoke-Native "terraform" @("fmt", "-check", "-recursive", $workRoot) | Out-Null
    Invoke-Native "terraform" @("-chdir=$workRoot", "init", "-backend=false", "-input=false", "-no-color") | Out-Null
    $terraformInitialized = $true
    Invoke-Native "terraform" @("-chdir=$workRoot", "validate", "-no-color") | Out-Null

    $network = New-NetworkFixture $runId
    $runtimeVariables = [ordered]@{
        name_prefix        = $runId
        run_id             = $runId
        localstack_endpoint = $LocalstackEndpoint
        subnet_ids         = $network.Subnets
    } | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText((Join-Path $workRoot "runtime.auto.tfvars.json"), $runtimeVariables, [Text.UTF8Encoding]::new($false))
    $inputArgs = @()
    $tests = Invoke-Native "terraform" (@("-chdir=$workRoot", "test", "-test-directory=tests", "-no-color") + $inputArgs)
    if ($tests.Text -notmatch "Success! 10 passed, 0 failed") {
        throw "Canonical Terraform 1.6 run count/result mismatch."
    }
    Write-Host "[unit] fmt/init/validate and 10 real-data-source Terraform 1.6 runs passed."

    if ($UnitOnly) {
        Write-Host "PASS challenge-21 UnitOnly"
        return
    }

    Remove-Item -LiteralPath (Join-Path $workRoot "tests") -Recurse -Force
    $baseArgs = @("-input=false", "-no-color") + $inputArgs
    $initialPlan = Join-Path $tempRoot "initial.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-out=$initialPlan") + $baseArgs) | Out-Null
    $initial = @(Get-PlanChanges $workRoot $initialPlan)
    if ($initial.Count -ne 8 -or @($initial | Where-Object { (@($_.change.actions) -join ",") -ne "create" }).Count -ne 0) {
        throw "Initial saved plan must contain three groups and five rule creates."
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $initialPlan) | Out-Null

    $reordered = Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-detailed-exitcode") + $baseArgs +
        @("-var=rules_csv_path=../fixtures/rules-reordered.csv")) @(0, 2)
    if ($reordered.ExitCode -ne 0) { throw "CSV reorder must produce a zero-change plan." }

    $ruleJson = (Invoke-Aws @("ec2", "describe-security-group-rules", "--filters", "Name=tag:RunId,Values=$runId",
        "Name=tag:RuleID,Values=api-from-web", "--output", "json")).Text | ConvertFrom-Json
    $rule = @($ruleJson.SecurityGroupRules)
    if ($rule.Count -ne 1) { throw "Unable to identify the api-from-web rule for drift." }
    Invoke-Aws @("ec2", "revoke-security-group-ingress", "--group-id", $rule[0].GroupId,
        "--security-group-rule-ids", $rule[0].SecurityGroupRuleId) | Out-Null

    $repairPlan = Join-Path $tempRoot "repair.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-out=$repairPlan") + $baseArgs) | Out-Null
    $repair = @(Get-PlanChanges $workRoot $repairPlan)
    $expected = 'aws_vpc_security_group_ingress_rule.this["api-from-web"]'
    if ($repair.Count -ne 1 -or $repair[0].address -cne $expected -or
        (@($repair[0].change.actions) -join ",") -cne "create") {
        throw "Repair plan must recreate only api-from-web."
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $repairPlan) | Out-Null

    $clean = Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-detailed-exitcode") + $baseArgs) @(0, 2)
    if ($clean.ExitCode -ne 0) { throw "Repair must end in a clean plan." }

    $destroyPlan = Join-Path $tempRoot "destroy.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-destroy", "-out=$destroyPlan") + $baseArgs) | Out-Null
    $destroy = @(Get-PlanChanges $workRoot $destroyPlan)
    if ($destroy.Count -ne 8 -or @($destroy | Where-Object { (@($_.change.actions) -join ",") -ne "delete" }).Count -ne 0) {
        throw "Saved destroy plan must contain exactly eight deletes."
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $destroyPlan) | Out-Null
    $terraformInitialized = $false

    $remainingGroups = ((Invoke-Aws @("ec2", "describe-security-groups", "--filters", "Name=tag:RunId,Values=$runId",
        "--query", "SecurityGroups[].GroupId", "--output", "text")).Text).Trim()
    $remainingRules = ((Invoke-Aws @("ec2", "describe-security-group-rules", "--filters", "Name=tag:RunId,Values=$runId",
        "--query", "SecurityGroupRules[].SecurityGroupRuleId", "--output", "text")).Text).Trim()
    if ($remainingGroups -or $remainingRules) { throw "Managed EC2 residue remains after destroy." }

    Write-Host "[e2e] external network data, saved plan, reorder no-op, real rule drift repair, and saved destroy passed."
    Write-Host "PASS challenge-21 (alignment A, difficulty 96/100)"
}
finally {
    if ($terraformInitialized -and (Test-Path -LiteralPath (Join-Path $workRoot "terraform.tfstate")) -and $null -ne $network) {
        try {
            Invoke-Native "terraform" @("-chdir=$workRoot", "destroy", "-auto-approve", "-input=false", "-no-color") @(0, 1) | Out-Null
        }
        catch {}
    }
    if ($null -ne $network) { try { Remove-NetworkFixture $network } catch {} }
    foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
    if (Test-Path -LiteralPath $tempRoot) {
        $resolved = [IO.Path]::GetFullPath($tempRoot)
        $base = [IO.Path]::GetFullPath($tempBase)
        if ($resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path $resolved -Leaf).StartsWith("tfpro-c21-grade-")) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
