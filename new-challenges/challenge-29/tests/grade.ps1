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
        $uri.IsDefaultPort -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        $uri.AbsolutePath -ne "/" -or
        $uri.Query -or $uri.Fragment) {
        throw "LocalstackEndpoint must be a loopback root origin with an explicit port."
    }
}

Assert-LoopbackEndpoint $LocalstackEndpoint

function Invoke-Native {
    param(
        [string]$File,
        [string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )
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

function Copy-CleanTree {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in @(".terraform", ".terraform.lock.hcl", "terraform.tfstate", "terraform.tfstate.backup", ".terraform.tfstate.lock.info") -or
            $item.Extension -eq ".tfplan") {
            continue
        }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            Copy-CleanTree $item.FullName $target
        }
        else {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}

function Get-PlanChanges {
    param([string]$WorkRoot, [string]$PlanPath)
    $shown = Invoke-Native "terraform" @("-chdir=$WorkRoot", "show", "-json", $PlanPath)
    $json = $shown.Text | ConvertFrom-Json
    if ($null -eq $json.resource_changes) { return @() }
    return @($json.resource_changes | Where-Object { (@($_.change.actions) -join ",") -ne "no-op" })
}

function Invoke-Aws {
    param([string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    return Invoke-Native "aws" (@("--endpoint-url", $LocalstackEndpoint) + $Arguments + @("--no-cli-pager")) $AllowedExitCodes
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
if ($allTf -match "aws_(dynamodb|sns|vpc|subnet|instance)") {
    throw "Candidate uses an AWS type outside this challenge contract."
}
$resourceTypes = @([regex]::Matches($allTf, '(?m)^\s*resource\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$allowedTypes = @("aws_iam_policy", "aws_iam_role", "aws_iam_role_policy_attachment", "aws_s3_bucket")
if (($resourceTypes -join "|") -cne ($allowedTypes -join "|") -or $allTf -match 'terraform_data') {
    throw "Managed resource types must match the official-list challenge contract."
}
if (([regex]::Matches($allTf, 'configuration_aliases\s*=\s*\[aws\.primary,\s*aws\.dr\]')).Count -ne 1 -or
    $allTf -notmatch 'configuration_aliases\s*=\s*\[aws\.workload\]') {
    throw "Nested modules must declare all provider slots explicitly."
}
if ($allTf -notmatch '(?m)^\s*aws\.dr\s*=\s*aws\.dr\s*$' -or
    $allTf -notmatch 'for\s+key,\s*contract\s+in\s+module\.primary\.contracts') {
    throw "The root and DR module provider/peer mappings are incomplete."
}
foreach ($slot in @("primary", "dr")) {
    $providerPattern = '(?ms)provider\s+"aws"\s*\{.*?alias\s*=\s*"' + $slot + '".*?^\}'
    $match = [regex]::Match($allTf, $providerPattern)
    if (-not $match.Success) { throw "Missing provider alias $slot." }
    $block = $match.Value
    foreach ($required in @('access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"', 's3_use_path_style\s*=\s*true',
            'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true',
            'skip_requesting_account_id\s*=\s*true', 'iam\s*=\s*var\.localstack_endpoint',
            's3\s*=\s*var\.localstack_endpoint', 'sts\s*=\s*var\.localstack_endpoint')) {
        if ($block -notmatch $required) { throw "Provider $slot is missing a LocalStack safety setting." }
    }
    if ($block -match '(?m)^\s*(sns|dynamodb|ec2)\s*=') {
        throw "Provider $slot exposes an endpoint outside iam,s3,sts."
    }
}

$testFile = Join-Path $PSScriptRoot "contracts.tftest.hcl"
$testText = [IO.File]::ReadAllText($testFile)
if ($testText -match "(?i)mock_provider|override_(resource|data|module)" -or
    ([regex]::Matches($testText, '(?m)^run\s+"')).Count -ne 8) {
    throw "Canonical suite must have exactly 8 Terraform 1.6 runs and no mocks or overrides."
}

$tempBase = [IO.Path]::GetTempPath()
$tempRoot = Join-Path $tempBase ("tfpro-c29-grade-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $tempRoot "candidate"
$pluginCache = Join-Path $tempRoot "plugin-cache"
$runId = "c29-" + [guid]::NewGuid().ToString("N").Substring(0, 10)
$terraformInitialized = $false
$envBefore = @{}
foreach ($name in @("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_DEFAULT_REGION", "AWS_EC2_METADATA_DISABLED", "TF_PLUGIN_CACHE_DIR")) {
    $envBefore[$name] = [Environment]::GetEnvironmentVariable($name)
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $pluginCache -Force | Out-Null
    $env:TF_PLUGIN_CACHE_DIR = $pluginCache
    Copy-CleanTree $candidateRoot $workRoot
    Copy-CleanTree $fixtureRoot (Join-Path $tempRoot "fixtures")
    New-Item -ItemType Directory -Path (Join-Path $workRoot "tests") -Force | Out-Null
    Copy-Item -LiteralPath $testFile -Destination (Join-Path $workRoot "tests/contracts.tftest.hcl") -Force

    Invoke-Native "terraform" @("fmt", "-check", "-recursive", $workRoot) | Out-Null
    Invoke-Native "terraform" @("-chdir=$workRoot", "init", "-backend=false", "-input=false", "-no-color") | Out-Null
    $terraformInitialized = $true
    Invoke-Native "terraform" @("-chdir=$workRoot", "validate", "-no-color") | Out-Null
    $tests = Invoke-Native "terraform" @("-chdir=$workRoot", "test", "-test-directory=tests", "-no-color")
    if ($tests.Text -notmatch "Success! 8 passed, 0 failed") {
        throw "Canonical Terraform 1.6 run count/result mismatch."
    }
    Write-Host "[unit] fmt/init/validate and 8 Terraform 1.6 runs passed."

    if ($UnitOnly) {
        Write-Host "PASS challenge-29 UnitOnly"
        return
    }

    $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + "/_localstack/health") -Method Get
    foreach ($service in @("iam", "s3", "sts")) {
        if ($null -eq $health.services.$service -or [string]$health.services.$service -notmatch "available|running") {
            throw "LocalStack service $service is unavailable."
        }
    }

    $env:AWS_ACCESS_KEY_ID = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION = "us-east-1"
    $env:AWS_EC2_METADATA_DISABLED = "true"

    Remove-Item -LiteralPath (Join-Path $workRoot "tests") -Recurse -Force
    $baseArgs = @("-input=false", "-no-color", "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
    $initialPlan = Join-Path $tempRoot "initial.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-out=$initialPlan") + $baseArgs) | Out-Null
    $initial = @(Get-PlanChanges $workRoot $initialPlan)
    if ($initial.Count -ne 24 -or @($initial | Where-Object { (@($_.change.actions) -join ",") -ne "create" }).Count -ne 0) {
        throw "Initial saved plan must contain exactly 24 creates."
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $initialPlan) | Out-Null

    foreach ($service in @("api", "metrics", "worker")) {
        foreach ($role in @("primary", "dr")) {
            Invoke-Aws @("s3api", "head-bucket", "--bucket", "$runId-$service-$role") | Out-Null
            Invoke-Aws @("iam", "get-role", "--role-name", "$runId-$service-$role") | Out-Null
        }
    }

    $reordered = Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-detailed-exitcode") + $baseArgs + @("-var=catalog_file=../fixtures/services-reordered.csv")) @(0, 2)
    if ($reordered.ExitCode -ne 0) { throw "CSV reorder must be a zero-change plan." }

    $drRole = "$runId-api-dr"
    $drPolicy = "arn:aws:iam::000000000000:policy/$runId-api-dr-artifact"
    Invoke-Aws @("iam", "detach-role-policy", "--role-name", $drRole, "--policy-arn", $drPolicy) | Out-Null
    $repairPlan = Join-Path $tempRoot "repair.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-out=$repairPlan") + $baseArgs) | Out-Null
    $repair = @(Get-PlanChanges $workRoot $repairPlan)
    $expectedAddress = 'module.replication.module.dr.aws_iam_role_policy_attachment.artifact["api"]'
    if ($repair.Count -ne 1 -or $repair[0].address -cne $expectedAddress -or
        (@($repair[0].change.actions) -join ",") -cne "create") {
        throw "Repair plan must recreate only the drifted DR api attachment."
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $repairPlan) | Out-Null

    $clean = Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-detailed-exitcode") + $baseArgs) @(0, 2)
    if ($clean.ExitCode -ne 0) { throw "Repair must end in a clean plan." }

    $destroyPlan = Join-Path $tempRoot "destroy.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-destroy", "-out=$destroyPlan") + $baseArgs) | Out-Null
    $destroy = @(Get-PlanChanges $workRoot $destroyPlan)
    if ($destroy.Count -ne 24 -or @($destroy | Where-Object { (@($_.change.actions) -join ",") -ne "delete" }).Count -ne 0) {
        throw "Saved destroy plan must contain exactly 24 deletes."
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $destroyPlan) | Out-Null
    $terraformInitialized = $false

    foreach ($service in @("api", "metrics", "worker")) {
        foreach ($role in @("primary", "dr")) {
            $bucket = Invoke-Aws @("s3api", "head-bucket", "--bucket", "$runId-$service-$role") @(254)
            if ($bucket.Text -notmatch '404|Not Found|NoSuchBucket') {
                throw "S3 bucket absence was not confirmed by an explicit not-found response."
            }
            $iamRole = Invoke-Aws @("iam", "get-role", "--role-name", "$runId-$service-$role") @(254)
            if ($iamRole.Text -notmatch 'NoSuchEntity|not found') {
                throw "IAM role absence was not confirmed by an explicit NoSuchEntity response."
            }
        }
    }

    Write-Host "[e2e] saved plan, reorder no-op, IAM drift repair, saved destroy, and zero residue passed."
    Write-Host "PASS challenge-29 (alignment A, difficulty 96/100)"
}
finally {
    if ($terraformInitialized -and (Test-Path -LiteralPath (Join-Path $workRoot "terraform.tfstate"))) {
        try {
            Invoke-Native "terraform" @("-chdir=$workRoot", "destroy", "-auto-approve", "-input=false", "-no-color",
                "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint") @(0, 1) | Out-Null
        }
        catch {}
    }
    foreach ($name in $envBefore.Keys) {
        [Environment]::SetEnvironmentVariable($name, $envBefore[$name])
    }
    if (Test-Path -LiteralPath $tempRoot) {
        $resolved = [IO.Path]::GetFullPath($tempRoot)
        $base = [IO.Path]::GetFullPath($tempBase)
        if ($resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path $resolved -Leaf).StartsWith("tfpro-c29-grade-")) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
