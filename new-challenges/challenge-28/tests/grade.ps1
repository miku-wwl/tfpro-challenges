param(
    [string]$Candidate = (Join-Path $PSScriptRoot "../starter"),
    [string]$LocalstackEndpoint = "http://localhost:4566"
)

$ErrorActionPreference = "Stop"

function Copy-CleanTree([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in @(".terraform", ".terraform.lock.hcl", "terraform.tfstate", "terraform.tfstate.backup", ".terraform.tfstate.lock.info") -or
            $item.Name -like "tests-generated*" -or $item.Extension -eq ".tfplan") {
            continue
        }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) { Copy-CleanTree $item.FullName $target } else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
    }
}

function Remove-HclComments([string]$Text) {
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

function Assert-LoopbackEndpoint([string]$Endpoint) {
    $uri = [Uri]$Endpoint
    if ($uri.Scheme -notin @("http", "https") -or $uri.Host -notin @("localhost", "127.0.0.1", "::1")) {
        throw "Refusing non-loopback LocalStack endpoint: $Endpoint"
    }
}

function Get-HclBlocks([string]$Text, [string]$HeaderPattern) {
    $blocks = [System.Collections.Generic.List[string]]::new()
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

function Test-ExactHclAssignment([string]$Block, [string]$Name, [string]$ValuePattern) {
    return [regex]::Matches($Block, "(?m)^\s*$([regex]::Escape($Name))\s*=\s*$ValuePattern\s*$").Count -eq 1
}

function Assert-ProviderRootContract(
    [string]$RootName,
    [string]$SafeRootText,
    [string[]]$ExpectedEndpoints,
    [bool]$RequireS3PathStyle
) {
    $providerBlocks = @(Get-HclBlocks $SafeRootText 'provider\s+"aws"\s*\{')
    if ($providerBlocks.Count -ne 2) {
        throw "$RootName must declare exactly two aws provider blocks: default and alias dr."
    }

    $aliasedBlocks = @($providerBlocks | Where-Object { $_ -match '(?m)^\s*alias\s*=' })
    $drBlocks = @($providerBlocks | Where-Object { Test-ExactHclAssignment $_ "alias" '"dr"' })
    $defaultBlocks = @($providerBlocks | Where-Object { $_ -notmatch '(?m)^\s*alias\s*=' })
    if ($aliasedBlocks.Count -ne 1 -or $drBlocks.Count -ne 1 -or $defaultBlocks.Count -ne 1) {
        throw "$RootName providers must contain one unaliased default and one unique literal alias dr."
    }

    $slots = @(
        @{ Name = "default"; Block = $defaultBlocks[0]; Region = 'var\.primary_region' },
        @{ Name = "dr"; Block = $drBlocks[0]; Region = 'var\.dr_region' }
    )
    foreach ($slot in $slots) {
        $block = [string]$slot.Block
        $required = @{
            region                      = [string]$slot.Region
            access_key                  = '"test"'
            secret_key                  = '"test"'
            skip_credentials_validation = 'true'
            skip_metadata_api_check     = 'true'
            skip_requesting_account_id  = 'true'
        }
        foreach ($entry in $required.GetEnumerator()) {
            if (-not (Test-ExactHclAssignment $block $entry.Key $entry.Value)) {
                throw "$RootName aws.$($slot.Name) must set literal $($entry.Key) correctly; dynamic values and cross-block counting are forbidden."
            }
        }
        if ($RequireS3PathStyle -and -not (Test-ExactHclAssignment $block "s3_use_path_style" 'true')) {
            throw "$RootName aws.$($slot.Name) must set s3_use_path_style=true."
        }
        if ($block -match '(?mi)^\s*(profile|token|shared_credentials_files|shared_config_files)\s*=' -or $block -match '(?mi)^\s*assume_role\s*\{') {
            throw "$RootName aws.$($slot.Name) contains a forbidden alternate credential source."
        }

        $endpointBlocks = @(Get-HclBlocks $block 'endpoints\s*\{')
        if ($endpointBlocks.Count -ne 1) { throw "$RootName aws.$($slot.Name) must contain exactly one endpoints block." }
        $endpointBlock = $endpointBlocks[0]
        $endpointKeys = @([regex]::Matches($endpointBlock, '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
        $expectedKeys = @($ExpectedEndpoints | Sort-Object)
        if (@(Compare-Object $expectedKeys $endpointKeys).Count -ne 0) {
            throw "$RootName aws.$($slot.Name) endpoints must be exactly: $($expectedKeys -join ', ')."
        }
        foreach ($service in $expectedKeys) {
            if (-not (Test-ExactHclAssignment $endpointBlock $service 'var\.localstack_endpoint')) {
                throw "$RootName aws.$($slot.Name) $service endpoint must reference var.localstack_endpoint."
            }
        }
    }
}

function Get-HclBlockBody([string]$Text, [string]$Kind, [string]$FirstLabel, [string]$SecondLabel = "") {
    $labels = if ($SecondLabel) { "\s+`"$([regex]::Escape($FirstLabel))`"\s+`"$([regex]::Escape($SecondLabel))`"" } else { "\s+`"$([regex]::Escape($FirstLabel))`"" }
    $pattern = "(?ms)^[ \t]*$Kind$labels\s*\{(?<body>.*?)(?=^[ \t]*(?:(?:resource|data|module|output|locals|check|variable|terraform)\b|provider\s+\x22)|\z)"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { throw "Missing $Kind block $FirstLabel $SecondLabel" }
    return $match.Groups["body"].Value
}

$LabRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$CandidateRoot = (Resolve-Path $Candidate).Path
$networkRootTf = (Get-ChildItem (Join-Path $CandidateRoot "network") -Filter *.tf -File | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$applicationRootTf = (Get-ChildItem (Join-Path $CandidateRoot "application") -Filter *.tf -File | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
Assert-LoopbackEndpoint $LocalstackEndpoint
Assert-ProviderRootContract -RootName "network" -SafeRootText (Remove-HclComments $networkRootTf) -ExpectedEndpoints @("ec2", "sts") -RequireS3PathStyle $false
Assert-ProviderRootContract -RootName "application" -SafeRootText (Remove-HclComments $applicationRootTf) -ExpectedEndpoints @("s3", "sns", "sts") -RequireS3PathStyle $true
$networkMain = Remove-HclComments (Get-Content -Raw (Join-Path $CandidateRoot "network/main.tf"))
$appMain = Remove-HclComments (Get-Content -Raw (Join-Path $CandidateRoot "application/main.tf"))
$drVpc = Get-HclBlockBody $networkMain "resource" "aws_vpc" "dr"
$drSubnet = Get-HclBlockBody $networkMain "resource" "aws_subnet" "dr"
if ($drVpc -notmatch '(?m)^[ \t]*provider\s*=\s*aws\.dr\s*$' -or
    $drSubnet -notmatch '(?m)^[ \t]*provider\s*=\s*aws\.dr\s*$') {
    throw "DR network resources must explicitly use aws.dr."
}
$drModule = Get-HclBlockBody $appMain "module" "application_dr"
if ($drModule -notmatch '(?m)^[ \t]*aws\s*=\s*aws\.dr\s*$') {
    throw "application_dr must explicitly map aws.dr."
}

$health = Invoke-RestMethod -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5
foreach ($service in @("ec2", "s3", "sns", "sts")) {
    if ($health.services.$service -notin @("available", "running")) { throw "LocalStack $service is unavailable." }
}

$tempBase = [IO.Path]::GetTempPath()
$temp = Join-Path $tempBase ("tfpro-c28-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $temp "candidate"
$network = Join-Path $workRoot "network"
$application = Join-Path $workRoot "application"
$runId = "c28" + [guid]::NewGuid().ToString("N").Substring(0, 10)
$failure = $null
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    Copy-CleanTree $CandidateRoot $workRoot
    Copy-CleanTree (Join-Path $LabRoot "fixtures") (Join-Path $temp "fixtures")

    $testCases = @(
        @{ Root = $network; Test = "network.tftest.hcl"; Passed = 1 },
        @{ Root = $application; Test = "application.tftest.hcl"; Passed = 6 }
    )
    foreach ($case in $testCases) {
        $testName = "tests-generated-$PID"
        $testDir = Join-Path $case.Root $testName
        New-Item -ItemType Directory -Force $testDir | Out-Null
        Copy-Item (Join-Path $PSScriptRoot $case.Test) $testDir -Force
        try {
            & terraform "-chdir=$($case.Root)" fmt -check -recursive
            if ($LASTEXITCODE) { throw "fmt failed for $($case.Root)" }
            & terraform "-chdir=$($case.Root)" init -backend=false -input=false -no-color
            if ($LASTEXITCODE) { throw "init failed for $($case.Root)" }
            & terraform "-chdir=$($case.Root)" validate -no-color
            if ($LASTEXITCODE) { throw "validate failed for $($case.Root)" }
            $testOutput = (& terraform "-chdir=$($case.Root)" test "-test-directory=$testName" -no-color 2>&1) -join "`n"
            Write-Host $testOutput
            $summaryCount = [regex]::Matches($testOutput, "(?m)^Success!\s+$($case.Passed) passed,\s+0 failed\.\s*$").Count
            $runPassCount = [regex]::Matches($testOutput, '(?m)^[ \t]+run\s+"[^"]+"\.\.\.\s+pass\s*$').Count
            if ($LASTEXITCODE -or $summaryCount -ne 1 -or $runPassCount -ne $case.Passed) {
                throw "Contract tests failed or were not discovered for $($case.Root)"
            }
        } finally {
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    & terraform "-chdir=$network" apply -auto-approve -input=false -no-color -var "run_id=$runId" -var "localstack_endpoint=$LocalstackEndpoint" | Out-Null
    if ($LASTEXITCODE) { throw "network apply failed" }
    & terraform "-chdir=$application" apply -auto-approve -input=false -no-color -var "run_id=$runId" -var "localstack_endpoint=$LocalstackEndpoint" | Out-Null
    if ($LASTEXITCODE) { throw "application apply failed" }
    foreach ($root in @($network, $application)) {
        & terraform "-chdir=$root" plan -detailed-exitcode -input=false -no-color -var "run_id=$runId" -var "localstack_endpoint=$LocalstackEndpoint" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "non-empty final plan for $root" }
    }
} catch {
    $failure = $_
} finally {
    foreach ($root in @($application, $network)) {
        if ((Test-Path $root) -and (Test-Path (Join-Path $root "terraform.tfstate"))) {
            & terraform "-chdir=$root" destroy -auto-approve -input=false -no-color -var "run_id=$runId" -var "localstack_endpoint=$LocalstackEndpoint" | Out-Null
            if ($LASTEXITCODE -and -not $failure) { $failure = "destroy failed for $root" }
        }
    }
    $resolved = [IO.Path]::GetFullPath($temp)
    if ($resolved.StartsWith([IO.Path]::GetFullPath($tempBase), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf).StartsWith("tfpro-c28-")) {
        Remove-Item $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if ($failure) { throw $failure }
Write-Host "PASS: Challenge 28 mock contracts and LocalStack dual-state E2E verified."
