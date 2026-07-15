[CmdletBinding()]
param(
    [string]$Candidate = (Join-Path $PSScriptRoot "../starter"),
    [string]$LocalstackEndpoint = "http://localhost:4566",
    [switch]$UnitOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

function Assert-LoopbackEndpoint {
    param([string]$Endpoint)
    $uri = $null
    $match = [regex]::Match($Endpoint, '\Ahttps?://(?:localhost|127\.0\.0\.1|\[::1\]):(?<port>[1-9][0-9]{0,4})\z')
    if (-not $match.Success -or [int]$match.Groups["port"].Value -gt 65535 -or
        -not [uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Host.Trim("[", "]").ToLowerInvariant() -notin @("localhost", "127.0.0.1", "::1") -or
        $uri.PathAndQuery -ne "/" -or $uri.UserInfo) {
        throw "LocalstackEndpoint must be a loopback root origin with an explicit valid port."
    }
}

Assert-LoopbackEndpoint $LocalstackEndpoint

function Invoke-Native {
    param([string]$File, [string[]]$Arguments, [int[]]$AllowedExitCodes = @(0))
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $lines = @(& $File @Arguments 2>&1 | ForEach-Object { "$_" })
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
            $item.Extension -in @(".tfplan", ".tfstate")) {
            continue
        }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) { Copy-CleanTree $item.FullName $target }
        else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Write-BackendConfig {
    param([string]$Path, [string]$Bucket, [string]$Key, [string]$Table)
    Write-Utf8 $Path @"
bucket = "$Bucket"
key = "$Key"
region = "us-east-1"
dynamodb_table = "$Table"
access_key = "test"
secret_key = "test"
use_path_style = true
skip_credentials_validation = true
skip_metadata_api_check = true
skip_requesting_account_id = true
endpoints = { s3 = "$LocalstackEndpoint", dynamodb = "$LocalstackEndpoint" }
"@
}

function Get-PlanChanges {
    param([string]$WorkRoot, [string]$PlanPath)
    $shown = Invoke-Native "terraform" @("-chdir=$WorkRoot", "show", "-json", $PlanPath)
    $json = $shown.Text | ConvertFrom-Json
    if ($null -eq $json.resource_changes) { return @() }
    return @($json.resource_changes | Where-Object { (@($_.change.actions) -join ",") -ne "no-op" })
}

function Assert-PlanActions {
    param([string]$WorkRoot, [string]$PlanPath, [int]$Count, [string]$Action, [string]$Label)
    $changes = @(Get-PlanChanges $WorkRoot $PlanPath)
    $wrong = @($changes | Where-Object { (@($_.change.actions) -join ",") -cne $Action })
    if ($changes.Count -ne $Count -or $wrong.Count -ne 0) {
        $summary = @($changes | ForEach-Object { "$($_.address):$(@($_.change.actions) -join ',')" }) -join "; "
        throw "$Label expected $Count $Action changes; found $summary"
    }
}

$challengeRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
$foundationSource = Join-Path $candidateRoot "foundation"
$applicationSource = Join-Path $candidateRoot "application"
$fixtureRoot = Join-Path $challengeRoot "fixtures"

if (-not (Test-Path -LiteralPath $foundationSource -PathType Container) -or
    -not (Test-Path -LiteralPath $applicationSource -PathType Container)) {
    throw "Candidate must contain foundation and application root modules."
}
if (@(Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter "*.ps1").Count -ne 0) {
    throw "Candidate work must contain Terraform HCL only."
}
$tfFiles = @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter "*.tf")
$allTf = ($tfFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join [Environment]::NewLine
if ($allTf -match "(?i)\bTODO\b|not implemented|incomplete") {
    throw "Candidate contains an unfinished marker."
}
if ($allTf -match 'aws_(vpc|subnet|sns|dynamodb)|terraform_data|state\s+(push|rm|mv)|force-unlock') {
    throw "Candidate contains an out-of-scope resource or manual state workaround."
}
$types = @([regex]::Matches($allTf, '(?m)^\s*resource\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($types -join "|") -cne "aws_s3_bucket|aws_s3_object") {
    throw "Managed AWS types must be exactly S3 bucket and object."
}
foreach ($backend in @((Join-Path $foundationSource "backend.tf"), (Join-Path $applicationSource "backend.tf"))) {
    $text = [IO.File]::ReadAllText($backend)
    if ($text -notmatch 'backend\s+"s3"\s*\{\s*\}' -or
        $text -match '(?i)bucket\s*=|key\s*=|region\s*=|endpoint|access_key|secret_key|dynamodb_table') {
        throw "Both roots require an empty partial S3 backend."
    }
}
if (([regex]::Matches($allTf, 'data\s+"terraform_remote_state"\s+"foundation"')).Count -ne 1 -or
    ([regex]::Matches($allTf, 'data\s+"aws_caller_identity"\s+"current"')).Count -ne 1) {
    throw "Application must use the official S3 remote-state and caller-identity data sources."
}
foreach ($required in @("access_key", "secret_key", "use_path_style", "skip_credentials_validation",
        "skip_metadata_api_check", "skip_requesting_account_id", "endpoints")) {
    if ($allTf -notmatch "(?m)^\s*$required\s*=") { throw "Remote state or provider contract is missing $required." }
}
if (([regex]::Matches($allTf, 'configuration_aliases\s*=\s*\[aws\.workload\]')).Count -ne 1 -or
    $allTf -notmatch 'providers\s*=\s*\{\s*aws\.workload\s*=\s*aws\.primary\s*\}' -or
    $allTf -notmatch 'providers\s*=\s*\{\s*aws\.workload\s*=\s*aws\.dr\s*\}') {
    throw "Application modules must route both provider aliases explicitly."
}
if ($allTf -match '(?m)^\s*(iam|sns|dynamodb|ec2)\s*=\s*var\.localstack_endpoint') {
    throw "Candidate provider endpoints must be exactly s3 and sts."
}

$testFile = Join-Path $PSScriptRoot "foundation.tftest.hcl"
$testText = [IO.File]::ReadAllText($testFile)
if ($testText -match "(?i)mock_provider|override_(resource|data|module)" -or
    ([regex]::Matches($testText, '(?m)^run\s+"')).Count -ne 8) {
    throw "Canonical suite must contain 8 Terraform 1.6 runs and no mocks or overrides."
}

$tempBase = [IO.Path]::GetTempPath()
$tempRoot = Join-Path $tempBase ("tfpro-c28-grade-" + [guid]::NewGuid().ToString("N"))
$unitFoundation = Join-Path $tempRoot "unit-foundation"
$unitApplication = Join-Path $tempRoot "unit-application"
$workRoot = Join-Path $tempRoot "work"
$foundationWork = Join-Path $workRoot "foundation"
$applicationWork = Join-Path $workRoot "application"
$pluginCache = Join-Path $tempRoot "plugin-cache"
$suffix = [guid]::NewGuid().ToString("N").Substring(0, 10)
$runId = "c28-$suffix"
$stateBucket = "tfpro-c28-state-$suffix"
$lockTable = "tfpro-c28-lock-$suffix"
$foundationInitialized = $false
$applicationInitialized = $false
$stateCreated = $false
$currentRevision = 1
$envBefore = @{}
foreach ($name in @("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_DEFAULT_REGION", "AWS_EC2_METADATA_DISABLED", "TF_PLUGIN_CACHE_DIR")) {
    $envBefore[$name] = [Environment]::GetEnvironmentVariable($name)
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $pluginCache -Force | Out-Null
    $env:TF_PLUGIN_CACHE_DIR = $pluginCache
    Copy-CleanTree $foundationSource $unitFoundation
    Copy-CleanTree $applicationSource $unitApplication
    New-Item -ItemType Directory -Path (Join-Path $unitFoundation "tests") -Force | Out-Null
    Copy-Item -LiteralPath $testFile -Destination (Join-Path $unitFoundation "tests/foundation.tftest.hcl") -Force

    Invoke-Native "terraform" @("fmt", "-check", "-recursive", $unitFoundation) | Out-Null
    Invoke-Native "terraform" @("fmt", "-check", "-recursive", $unitApplication) | Out-Null
    Invoke-Native "terraform" @("-chdir=$unitFoundation", "init", "-backend=false", "-input=false", "-no-color") | Out-Null
    Invoke-Native "terraform" @("-chdir=$unitApplication", "init", "-backend=false", "-input=false", "-no-color") | Out-Null
    Invoke-Native "terraform" @("-chdir=$unitFoundation", "validate", "-no-color") | Out-Null
    Invoke-Native "terraform" @("-chdir=$unitApplication", "validate", "-no-color") | Out-Null
    $tests = Invoke-Native "terraform" @("-chdir=$unitFoundation", "test", "-test-directory=tests", "-no-color")
    if ($tests.Text -notmatch "Success! 8 passed, 0 failed") {
        throw "Canonical Terraform 1.6 run count/result mismatch."
    }
    Write-Host "[unit] both roots fmt/init/validate; 8 Terraform 1.6 foundation runs passed."

    if ($UnitOnly) {
        Write-Host "PASS challenge-28 UnitOnly"
        return
    }

    $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + "/_localstack/health") -Method Get
    foreach ($service in @("s3", "dynamodb", "sts")) {
        if ($null -eq $health.services.$service -or [string]$health.services.$service -notmatch "available|running") {
            throw "LocalStack service $service is unavailable."
        }
    }
    $env:AWS_ACCESS_KEY_ID = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION = "us-east-1"
    $env:AWS_EC2_METADATA_DISABLED = "true"

    Invoke-Aws @("s3api", "create-bucket", "--bucket", $stateBucket, "--region", "us-east-1") | Out-Null
    Invoke-Aws @("dynamodb", "create-table", "--table-name", $lockTable,
        "--attribute-definitions", "AttributeName=LockID,AttributeType=S",
        "--key-schema", "AttributeName=LockID,KeyType=HASH", "--billing-mode", "PAY_PER_REQUEST",
        "--region", "us-east-1") | Out-Null
    Invoke-Aws @("dynamodb", "wait", "table-exists", "--table-name", $lockTable, "--region", "us-east-1") | Out-Null
    $stateCreated = $true

    Copy-CleanTree $foundationSource $foundationWork
    Copy-CleanTree $applicationSource $applicationWork
    Copy-CleanTree $fixtureRoot (Join-Path $workRoot "fixtures")

    $foundationConfig = Join-Path $tempRoot "foundation.backend.hcl"
    $applicationConfig = Join-Path $tempRoot "application.backend.hcl"
    Write-BackendConfig $foundationConfig $stateBucket "foundation/terraform.tfstate" $lockTable
    Write-BackendConfig $applicationConfig $stateBucket "application/terraform.tfstate" $lockTable
    Invoke-Native "terraform" @("-chdir=$foundationWork", "init", "-input=false", "-no-color", "-backend-config=$foundationConfig") | Out-Null
    $foundationInitialized = $true

    $foundationBase = @("-input=false", "-no-color", "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
    $foundationV1 = Join-Path $tempRoot "foundation-v1.tfplan"
    Invoke-Native "terraform" (@("-chdir=$foundationWork", "plan", "-out=$foundationV1") + $foundationBase + @("-var=platform_revision=1")) | Out-Null
    Assert-PlanActions $foundationWork $foundationV1 4 "create" "foundation v1"
    Invoke-Native "terraform" @("-chdir=$foundationWork", "apply", "-input=false", "-auto-approve", "-no-color", $foundationV1) | Out-Null

    Invoke-Native "terraform" @("-chdir=$applicationWork", "init", "-input=false", "-no-color", "-backend-config=$applicationConfig") | Out-Null
    $applicationInitialized = $true
    $applicationBase = @("-input=false", "-no-color", "-var=run_id=$runId", "-var=state_bucket=$stateBucket",
        "-var=localstack_endpoint=$LocalstackEndpoint")
    $applicationV1 = Join-Path $tempRoot "application-v1.tfplan"
    Invoke-Native "terraform" (@("-chdir=$applicationWork", "plan", "-out=$applicationV1") + $applicationBase +
        @("-var=expected_platform_revision=1")) | Out-Null
    Assert-PlanActions $applicationWork $applicationV1 8 "create" "application v1"
    Invoke-Native "terraform" @("-chdir=$applicationWork", "apply", "-input=false", "-auto-approve", "-no-color", $applicationV1) | Out-Null

    foreach ($bucket in @("tfpro-c28-$runId-api-primary", "tfpro-c28-$runId-worker-dr",
            "tfpro-c28-$runId-metrics-primary", "tfpro-c28-$runId-metrics-dr")) {
        Invoke-Aws @("s3api", "head-object", "--bucket", $bucket, "--key", "platform/receipt.json") | Out-Null
    }

    $reordered = Invoke-Native "terraform" (@("-chdir=$applicationWork", "plan", "-detailed-exitcode") + $applicationBase +
        @("-var=expected_platform_revision=1", "-var=catalog_file=../fixtures/applications-reordered.csv")) @(0, 2)
    if ($reordered.ExitCode -ne 0) { throw "Application CSV reorder must be a zero-change plan." }

    $premature = Invoke-Native "terraform" (@("-chdir=$applicationWork", "plan") + $applicationBase +
        @("-var=expected_platform_revision=2")) @(1)
    if ($premature.Text -notmatch "Foundation platform revision is not the expected revision") {
        throw "Application did not reject revision 2 before foundation publication."
    }

    $foundationV2 = Join-Path $tempRoot "foundation-v2.tfplan"
    Invoke-Native "terraform" (@("-chdir=$foundationWork", "plan", "-out=$foundationV2") + $foundationBase + @("-var=platform_revision=2")) | Out-Null
    Assert-PlanActions $foundationWork $foundationV2 2 "update" "foundation v2"
    Invoke-Native "terraform" @("-chdir=$foundationWork", "apply", "-input=false", "-auto-approve", "-no-color", $foundationV2) | Out-Null
    $currentRevision = 2

    $stale = Invoke-Native "terraform" (@("-chdir=$applicationWork", "plan") + $applicationBase +
        @("-var=expected_platform_revision=1")) @(1)
    if ($stale.Text -notmatch "Foundation platform revision is not the expected revision") {
        throw "Application did not reject its stale revision 1 expectation."
    }

    $applicationV2 = Join-Path $tempRoot "application-v2.tfplan"
    Invoke-Native "terraform" (@("-chdir=$applicationWork", "plan", "-out=$applicationV2") + $applicationBase +
        @("-var=expected_platform_revision=2")) | Out-Null
    Assert-PlanActions $applicationWork $applicationV2 4 "update" "application v2"
    Invoke-Native "terraform" @("-chdir=$applicationWork", "apply", "-input=false", "-auto-approve", "-no-color", $applicationV2) | Out-Null

    $foundationClean = Invoke-Native "terraform" (@("-chdir=$foundationWork", "plan", "-detailed-exitcode") + $foundationBase +
        @("-var=platform_revision=2")) @(0, 2)
    $applicationClean = Invoke-Native "terraform" (@("-chdir=$applicationWork", "plan", "-detailed-exitcode") + $applicationBase +
        @("-var=expected_platform_revision=2")) @(0, 2)
    if ($foundationClean.ExitCode -ne 0 -or $applicationClean.ExitCode -ne 0) {
        throw "Foundation or application final plan is not clean."
    }

    $applicationDestroy = Join-Path $tempRoot "application-destroy.tfplan"
    Invoke-Native "terraform" (@("-chdir=$applicationWork", "plan", "-destroy", "-out=$applicationDestroy") + $applicationBase +
        @("-var=expected_platform_revision=2")) | Out-Null
    Assert-PlanActions $applicationWork $applicationDestroy 8 "delete" "application destroy"
    Invoke-Native "terraform" @("-chdir=$applicationWork", "apply", "-input=false", "-auto-approve", "-no-color", $applicationDestroy) | Out-Null
    $applicationInitialized = $false

    $foundationDestroy = Join-Path $tempRoot "foundation-destroy.tfplan"
    Invoke-Native "terraform" (@("-chdir=$foundationWork", "plan", "-destroy", "-out=$foundationDestroy") + $foundationBase +
        @("-var=platform_revision=2")) | Out-Null
    Assert-PlanActions $foundationWork $foundationDestroy 4 "delete" "foundation destroy"
    Invoke-Native "terraform" @("-chdir=$foundationWork", "apply", "-input=false", "-auto-approve", "-no-color", $foundationDestroy) | Out-Null
    $foundationInitialized = $false

    foreach ($bucket in @("tfpro-c28-$runId-api-primary", "tfpro-c28-$runId-worker-dr",
            "tfpro-c28-$runId-metrics-primary", "tfpro-c28-$runId-metrics-dr",
            "tfpro-c28-$runId-primary", "tfpro-c28-$runId-dr")) {
        $remaining = Invoke-Aws @("s3api", "head-bucket", "--bucket", $bucket) @(254)
        if ($remaining.Text -notmatch '404|Not Found|NoSuchBucket') {
            throw "Explicit not-found response was not received for workload bucket $bucket."
        }
    }

    Invoke-Aws @("dynamodb", "delete-table", "--table-name", $lockTable, "--region", "us-east-1") | Out-Null
    Invoke-Aws @("dynamodb", "wait", "table-not-exists", "--table-name", $lockTable, "--region", "us-east-1") | Out-Null
    Invoke-Aws @("s3", "rm", "s3://$stateBucket", "--recursive") | Out-Null
    Invoke-Aws @("s3api", "delete-bucket", "--bucket", $stateBucket) | Out-Null
    $stateCreated = $false

    Write-Host "[e2e] dual S3 state, provider routing, CSV no-op, revision propagation, ordered saved destroy passed."
    Write-Host "PASS challenge-28 (alignment A, difficulty 97/100)"
}
finally {
    if ($applicationInitialized -and (Test-Path -LiteralPath $applicationWork)) {
        try {
            Invoke-Native "terraform" @("-chdir=$applicationWork", "destroy", "-auto-approve", "-input=false", "-no-color",
                "-var=run_id=$runId", "-var=state_bucket=$stateBucket", "-var=localstack_endpoint=$LocalstackEndpoint",
                "-var=expected_platform_revision=$currentRevision") @(0, 1) | Out-Null
        }
        catch {}
    }
    if ($foundationInitialized -and (Test-Path -LiteralPath $foundationWork)) {
        try {
            Invoke-Native "terraform" @("-chdir=$foundationWork", "destroy", "-auto-approve", "-input=false", "-no-color",
                "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint",
                "-var=platform_revision=$currentRevision") @(0, 1) | Out-Null
        }
        catch {}
    }
    if ($stateCreated) {
        try { Invoke-Aws @("dynamodb", "delete-table", "--table-name", $lockTable, "--region", "us-east-1") @(0, 255) | Out-Null } catch {}
        try { Invoke-Aws @("s3", "rm", "s3://$stateBucket", "--recursive") @(0, 255) | Out-Null } catch {}
        try { Invoke-Aws @("s3api", "delete-bucket", "--bucket", $stateBucket) @(0, 255) | Out-Null } catch {}
    }
    foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
    if (Test-Path -LiteralPath $tempRoot) {
        $resolved = [IO.Path]::GetFullPath($tempRoot)
        $base = [IO.Path]::GetFullPath($tempBase)
        if ($resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path $resolved -Leaf).StartsWith("tfpro-c28-grade-")) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
