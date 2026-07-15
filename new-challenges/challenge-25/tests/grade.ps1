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

function Get-PlanJson {
    param([string]$WorkRoot, [string]$PlanPath)
    $shown = Invoke-Native "terraform" @("-chdir=$WorkRoot", "show", "-json", $PlanPath)
    return ($shown.Text | ConvertFrom-Json)
}

function Get-Changes {
    param($PlanJson)
    if ($null -eq $PlanJson.resource_changes) { return @() }
    return @($PlanJson.resource_changes | Where-Object { (@($_.change.actions) -join ",") -ne "no-op" })
}

function Create-Bucket {
    param([string]$Name, [string]$RunId)
    Invoke-Aws @("s3api", "create-bucket", "--bucket", $Name, "--region", "us-east-1") | Out-Null
    $tagging = "TagSet=[{Key=Challenge,Value=25},{Key=ManagedBy,Value=terraform},{Key=RunId,Value=$RunId},{Key=Role,Value=config}]"
    Invoke-Aws @("s3api", "put-bucket-tagging", "--bucket", $Name, "--tagging", $tagging) | Out-Null
}

function Remove-Bucket {
    param([string]$Name)
    Invoke-Aws @("s3", "rm", "s3://$Name", "--recursive") @(0, 255) | Out-Null
    Invoke-Aws @("s3api", "delete-bucket", "--bucket", $Name) @(0, 254, 255) | Out-Null
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
if ($allTf -match "aws_dynamodb|terraform_data|prevent_destroy|state\s+(rm|mv|push)|force-unlock") {
    throw "Candidate contains an out-of-scope resource or manual state workaround."
}
$types = @([regex]::Matches($allTf, '(?m)^\s*resource\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($types -join "|") -cne "aws_s3_bucket|aws_s3_object") {
    throw "Managed AWS resources must be exactly S3 bucket and object."
}
if (([regex]::Matches($allTf, '(?ms)import\s*\{.*?to\s*=\s*aws_s3_bucket\.config.*?id\s*=\s*local\.bucket_name.*?\}')).Count -ne 1) {
    throw "A static Terraform 1.6 declarative import must adopt the existing bucket."
}
foreach ($required in @('replace_triggered_by\s*=\s*\[aws_s3_object\.revision_pointer\]', 'precondition\s*\{', 'postcondition\s*\{',
        'etag\s*=\s*md5\(', 'source_hash\s*=\s*local\.config_sha256')) {
    if ($allTf -notmatch $required) { throw "Missing lifecycle/content contract: $required" }
}
foreach ($required in @('access_key\s*=\s*"test"', 'secret_key\s*=\s*"test"', 's3_use_path_style\s*=\s*true',
        'skip_credentials_validation\s*=\s*true', 'skip_metadata_api_check\s*=\s*true',
        'skip_requesting_account_id\s*=\s*true', 's3\s*=\s*var\.localstack_endpoint',
        'sts\s*=\s*var\.localstack_endpoint')) {
    if ($allTf -notmatch $required) { throw "Provider safety contract is incomplete." }
}
if ($allTf -match '(?m)^\s*(iam|sns|dynamodb|ec2)\s*=\s*var\.localstack_endpoint') {
    throw "Provider endpoints must be exactly s3 and sts."
}

$testFile = Join-Path $PSScriptRoot "lifecycle.tftest.hcl"
$testText = [IO.File]::ReadAllText($testFile)
if ($testText -match "(?i)mock_provider|override_(resource|data|module)" -or
    ([regex]::Matches($testText, '(?m)^run\s+"')).Count -ne 8) {
    throw "Canonical suite must contain 8 Terraform 1.6 runs and no mocks or overrides."
}

$health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + "/_localstack/health") -Method Get
foreach ($service in @("s3", "sts")) {
    if ($null -eq $health.services.$service -or [string]$health.services.$service -notmatch "available|running") {
        throw "LocalStack service $service is unavailable."
    }
}

$tempBase = [IO.Path]::GetTempPath()
$tempRoot = Join-Path $tempBase ("tfpro-c25-grade-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $tempRoot "candidate"
$pluginCache = Join-Path $tempRoot "plugin-cache"
$suffix = [guid]::NewGuid().ToString("N").Substring(0, 10)
$unitPrefix = "u25-$suffix"
$unitBucket = "$unitPrefix-dev-config"
$runPrefix = "c25-$suffix"
$bucket = "$runPrefix-dev-config"
$unitBucketCreated = $false
$bucketCreated = $false
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
    Copy-Item -LiteralPath $testFile -Destination (Join-Path $workRoot "tests/lifecycle.tftest.hcl") -Force

    Invoke-Native "terraform" @("fmt", "-check", "-recursive", $workRoot) | Out-Null
    Invoke-Native "terraform" @("-chdir=$workRoot", "init", "-backend=false", "-input=false", "-no-color") | Out-Null
    $terraformInitialized = $true
    Invoke-Native "terraform" @("-chdir=$workRoot", "validate", "-no-color") | Out-Null

    Create-Bucket $unitBucket $unitPrefix
    $unitBucketCreated = $true
    $tests = Invoke-Native "terraform" @("-chdir=$workRoot", "test", "-test-directory=tests", "-no-color",
        "-var=name_prefix=$unitPrefix", "-var=localstack_endpoint=$LocalstackEndpoint")
    if ($tests.Text -notmatch "Success! 8 passed, 0 failed") {
        throw "Canonical Terraform 1.6 run count/result mismatch."
    }
    Remove-Bucket $unitBucket
    $unitBucketCreated = $false
    Write-Host "[unit] fmt/init/validate and 8 Terraform 1.6 import-aware runs passed."

    if ($UnitOnly) {
        Write-Host "PASS challenge-25 UnitOnly"
        return
    }

    Remove-Item -LiteralPath (Join-Path $workRoot "tests") -Recurse -Force
    Create-Bucket $bucket $runPrefix
    $bucketCreated = $true

    $baseArgs = @("-input=false", "-no-color", "-var=name_prefix=$runPrefix", "-var=localstack_endpoint=$LocalstackEndpoint")
    $v1 = Join-Path $fixtureRoot "config-v1.json"
    $v2 = Join-Path $fixtureRoot "config-v2.json"
    $initialPlan = Join-Path $tempRoot "initial.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-out=$initialPlan") + $baseArgs + @("-var=config_path=$v1")) | Out-Null
    $initialJson = Get-PlanJson $workRoot $initialPlan
    $initialChanges = @(Get-Changes $initialJson)
    if ($initialChanges.Count -ne 3 -or @($initialChanges | Where-Object { (@($_.change.actions) -join ",") -ne "create" }).Count -ne 0) {
        $summary = @($initialJson.resource_changes | ForEach-Object { "$($_.address):$(@($_.change.actions) -join ','):import=$($null -ne $_.change.importing)" }) -join '; '
        throw "Initial plan must import the bucket and create exactly three objects. Found $summary"
    }
    $bucketChange = @($initialJson.resource_changes | Where-Object { $_.address -eq "aws_s3_bucket.config" })
    if ($bucketChange.Count -ne 1 -or $null -eq $bucketChange[0].change.importing) {
        throw "Initial saved plan does not contain the declarative bucket import."
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $initialPlan) | Out-Null

    $v2Plan = Join-Path $tempRoot "v2.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-out=$v2Plan") + $baseArgs +
        @("-var=config_version=2", "-var=config_path=$v2")) | Out-Null
    $v2Changes = @(Get-Changes (Get-PlanJson $workRoot $v2Plan))
    if ($v2Changes.Count -ne 4 -or
        @($v2Changes | Where-Object { $_.address -eq "aws_s3_object.current" -and (@($_.change.actions) -join ",") -match "delete,create|create,delete" }).Count -ne 1) {
        $summary = @($v2Changes | ForEach-Object { "$($_.address):$(@($_.change.actions) -join ',')" }) -join '; '
        throw "v2 plan must rotate one immutable object and replace current exactly once. Found $summary"
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $v2Plan) | Out-Null

    $driftFile = Join-Path $tempRoot "drift.json"
    [IO.File]::WriteAllText($driftFile, '{"tampered":true}', [Text.UTF8Encoding]::new($false))
    Invoke-Aws @("s3api", "put-object", "--bucket", $bucket, "--key", "config/current.json", "--body", $driftFile,
        "--content-type", "application/json") | Out-Null

    $refreshPlan = Join-Path $tempRoot "refresh.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-refresh-only", "-out=$refreshPlan") + $baseArgs +
        @("-var=config_version=2", "-var=config_path=$v2")) | Out-Null
    $refreshJson = Get-PlanJson $workRoot $refreshPlan
    if (@($refreshJson.resource_drift | Where-Object { $_.address -eq "aws_s3_object.current" }).Count -ne 1) {
        throw "Refresh-only plan must record drift for current and no other address."
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $refreshPlan) | Out-Null

    $repairPlan = Join-Path $tempRoot "repair.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-out=$repairPlan") + $baseArgs +
        @("-var=config_version=2", "-var=config_path=$v2")) | Out-Null
    $repairChanges = @(Get-Changes (Get-PlanJson $workRoot $repairPlan))
    if ($repairChanges.Count -ne 1 -or $repairChanges[0].address -ne "aws_s3_object.current") {
        throw "Repair plan must change only aws_s3_object.current."
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $repairPlan) | Out-Null

    $download = Join-Path $tempRoot "current.json"
    Invoke-Aws @("s3api", "get-object", "--bucket", $bucket, "--key", "config/current.json", $download) | Out-Null
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actualDigest = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($download)))).Replace("-", "").ToLowerInvariant() }
    finally { $sha.Dispose() }
    $identity = (Invoke-Native "terraform" @("-chdir=$workRoot", "output", "-raw", "revision_identity")).Text.Trim()
    if (-not $identity.EndsWith($actualDigest, [StringComparison]::Ordinal)) {
        throw "Repaired current payload digest does not match the Terraform contract."
    }

    $clean = Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-detailed-exitcode") + $baseArgs +
        @("-var=config_version=2", "-var=config_path=$v2")) @(0, 2)
    if ($clean.ExitCode -ne 0) { throw "Final plan is not clean." }

    $destroyPlan = Join-Path $tempRoot "destroy.tfplan"
    Invoke-Native "terraform" (@("-chdir=$workRoot", "plan", "-destroy", "-out=$destroyPlan") + $baseArgs +
        @("-var=config_version=2", "-var=config_path=$v2")) | Out-Null
    $destroyChanges = @(Get-Changes (Get-PlanJson $workRoot $destroyPlan))
    if ($destroyChanges.Count -ne 4 -or @($destroyChanges | Where-Object { (@($_.change.actions) -join ",") -ne "delete" }).Count -ne 0) {
        throw "Saved destroy plan must contain exactly four deletes."
    }
    Invoke-Native "terraform" @("-chdir=$workRoot", "apply", "-input=false", "-auto-approve", "-no-color", $destroyPlan) | Out-Null
    $terraformInitialized = $false
    $bucketCreated = $false

    $remaining = Invoke-Aws @("s3api", "head-bucket", "--bucket", $bucket) @(254)
    if ($remaining.Text -notmatch '404|Not Found|NoSuchBucket') {
        throw "Bucket absence was not confirmed by an explicit not-found response."
    }

    Write-Host "[e2e] declarative import, version replacement, refresh-only drift, precise repair, and saved destroy passed."
    Write-Host "PASS challenge-25 (alignment A, difficulty 96/100)"
}
finally {
    if ($unitBucketCreated) { try { Remove-Bucket $unitBucket } catch {} }
    if ($terraformInitialized -and (Test-Path -LiteralPath (Join-Path $workRoot "terraform.tfstate"))) {
        try {
            Invoke-Native "terraform" @("-chdir=$workRoot", "destroy", "-auto-approve", "-input=false", "-no-color",
                "-var=name_prefix=$runPrefix", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=config_version=2",
                "-var=config_path=$(Join-Path $fixtureRoot 'config-v2.json')") @(0, 1) | Out-Null
        }
        catch {}
    }
    if ($bucketCreated) { try { Remove-Bucket $bucket } catch {} }
    foreach ($name in $envBefore.Keys) { [Environment]::SetEnvironmentVariable($name, $envBefore[$name]) }
    if (Test-Path -LiteralPath $tempRoot) {
        $resolved = [IO.Path]::GetFullPath($tempRoot)
        $base = [IO.Path]::GetFullPath($tempBase)
        if ($resolved.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path $resolved -Leaf).StartsWith("tfpro-c25-grade-")) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
