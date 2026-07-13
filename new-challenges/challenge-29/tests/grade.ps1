param(
    [string]$Candidate = (Join-Path $PSScriptRoot "../starter")
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

function Get-TopLevelAwsProviderBlocks([string]$Text) {
    $blocks = @()
    $headers = [regex]::Matches($Text, '(?m)^[ \t]*provider[ \t]+"aws"[ \t]*\{')
    foreach ($header in $headers) {
        $openBrace = $header.Index + $header.Value.LastIndexOf('{')
        $depth = 0
        $inString = $false
        $escaped = $false
        $closed = $false
        for ($index = $openBrace; $index -lt $Text.Length; $index++) {
            $character = $Text[$index]
            if ($inString) {
                if ($escaped) { $escaped = $false }
                elseif ($character -eq [char]92) { $escaped = $true }
                elseif ($character -eq '"') { $inString = $false }
                continue
            }
            if ($character -eq '"') { $inString = $true }
            elseif ($character -eq '{') { $depth++ }
            elseif ($character -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $blocks += $Text.Substring($header.Index, $index - $header.Index + 1)
                    $closed = $true
                    break
                }
            }
        }
        if (-not $closed) { throw "Unclosed AWS provider block" }
    }
    return $blocks
}

function Assert-ExactProviderAssignment([string]$Block, [string]$Name, [string]$ExpectedPattern, [string]$Alias) {
    $allAssignments = [regex]::Matches($Block, '(?m)^\s*' + [regex]::Escape($Name) + '\s*=')
    $exactAssignments = [regex]::Matches($Block, '(?m)^\s*' + [regex]::Escape($Name) + '\s*=\s*' + $ExpectedPattern + '\s*$')
    if ($allAssignments.Count -ne 1 -or $exactAssignments.Count -ne 1) {
        throw "AWS provider $Alias must set $Name exactly once to the required literal/expression"
    }
}

function Assert-AwsProviderBlocks([string]$RootConfiguration) {
    $blocks = @(Get-TopLevelAwsProviderBlocks $RootConfiguration)
    if ($blocks.Count -ne 2) { throw "Root module must contain exactly two AWS provider blocks" }
    $providers = @{}
    foreach ($block in $blocks) {
        $aliasAssignments = [regex]::Matches($block, '(?m)^\s*alias\s*=')
        $aliasMatches = [regex]::Matches($block, '(?m)^\s*alias\s*=\s*"(primary|dr)"\s*$')
        if ($aliasAssignments.Count -ne 1 -or $aliasMatches.Count -ne 1) {
            throw "Every AWS provider must have exactly one literal primary or dr alias; default and dynamic aliases are forbidden"
        }
        $alias = $aliasMatches[0].Groups[1].Value
        if ($providers.ContainsKey($alias)) { throw "AWS provider alias $alias must be unique" }
        $providers[$alias] = $block

        $expectedRegion = if ($alias -eq "primary") { 'var\.primary_region' } else { 'var\.dr_region' }
        Assert-ExactProviderAssignment $block "region" $expectedRegion $alias
        Assert-ExactProviderAssignment $block "access_key" '"test"' $alias
        Assert-ExactProviderAssignment $block "secret_key" '"test"' $alias
        foreach ($flag in @("skip_credentials_validation", "skip_metadata_api_check", "skip_requesting_account_id", "s3_use_path_style")) {
            Assert-ExactProviderAssignment $block $flag 'true' $alias
        }
        foreach ($service in @("s3", "sns", "dynamodb", "sts")) {
            Assert-ExactProviderAssignment $block $service 'var\.localstack_endpoint' $alias
        }
        if ($block -match '(?m)^\s*(profile|shared_credentials_files|shared_config_files|token|web_identity_token_file)\s*=' -or
            $block -match '(?m)^\s*(assume_role|assume_role_with_web_identity)\s*\{') {
            throw "AWS provider $alias contains a forbidden real-credential channel"
        }
    }
    if (-not $providers.ContainsKey("primary") -or -not $providers.ContainsKey("dr") -or $providers.Count -ne 2) {
        throw "AWS provider aliases must be exactly primary and dr"
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
$rootTf = (Get-ChildItem $CandidateRoot -Filter *.tf -File | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$safeTf = Remove-HclComments $rootTf
Assert-AwsProviderBlocks $safeTf
$endpointVariable = Get-HclBlockBody $safeTf "variable" "localstack_endpoint"
$endpointDefaults = [regex]::Matches($endpointVariable, '(?m)^\s*default\s*=')
$exactEndpointDefault = [regex]::Matches($endpointVariable, '(?m)^\s*default\s*=\s*"http://localhost:4566"\s*$')
if ($endpointDefaults.Count -ne 1 -or $exactEndpointDefault.Count -ne 1) {
    throw "localstack_endpoint must have exactly one comment-safe default of http://localhost:4566"
}
$rootMain = Remove-HclComments (Get-Content -Raw (Join-Path $CandidateRoot "main.tf"))
$replicationMain = Remove-HclComments (Get-Content -Raw (Join-Path $CandidateRoot "modules/replication/main.tf"))
$replicationVersions = Remove-HclComments (Get-Content -Raw (Join-Path $CandidateRoot "modules/replication/versions.tf"))
$rootReplication = Get-HclBlockBody $rootMain "module" "replication"
if ($rootReplication -notmatch '(?m)^[ \t]*aws\.dr\s*=\s*aws\.dr\s*$') {
    throw "The root replication module must map aws.dr to aws.dr."
}
if ($replicationVersions -notmatch 'configuration_aliases\s*=\s*\[aws\.primary,\s*aws\.dr\]') {
    throw "The replication module must declare both provider aliases."
}
$drReplication = Get-HclBlockBody $replicationMain "module" "dr"
if ($drReplication -notmatch '(?m)^[ \t]*providers\s*=\s*\{\s*aws\.workload\s*=\s*aws\.dr\s*\}' -or
    $drReplication -notmatch '(?s)peer_topics\s*=\s*\{\s*for\s+key,\s*contract\s+in\s+module\.primary\.contracts') {
    throw "The DR regional module must receive aws.dr and keyed primary topic contracts."
}

$health = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -TimeoutSec 5
foreach ($service in @("s3", "sns", "dynamodb", "sts")) {
    if ($health.services.$service -notin @("available", "running")) { throw "LocalStack $service is unavailable." }
}

$tempBase = [IO.Path]::GetTempPath()
$temp = Join-Path $tempBase ("tfpro-c29-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $temp "candidate"
$runId = "c29" + [guid]::NewGuid().ToString("N").Substring(0, 10)
$failure = $null
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    Copy-CleanTree $CandidateRoot $workRoot
    Copy-CleanTree (Join-Path $LabRoot "fixtures") (Join-Path $temp "fixtures")

    $testName = "tests-generated-$PID"
    $testDir = Join-Path $workRoot $testName
    New-Item -ItemType Directory -Force $testDir | Out-Null
    Copy-Item (Join-Path $PSScriptRoot "contracts.tftest.hcl") $testDir -Force

    & terraform "-chdir=$workRoot" fmt -check -recursive
    if ($LASTEXITCODE) { throw "fmt failed" }
    & terraform "-chdir=$workRoot" init -backend=false -input=false -no-color
    if ($LASTEXITCODE) { throw "init failed" }
    & terraform "-chdir=$workRoot" validate -no-color
    if ($LASTEXITCODE) { throw "validate failed" }
    $testOutput = (& terraform "-chdir=$workRoot" test "-test-directory=$testName" -no-color 2>&1) -join "`n"
    Write-Host $testOutput
    $summaryCount = [regex]::Matches($testOutput, '(?m)^Success!\s+5 passed,\s+0 failed\.\s*$').Count
    $runPassCount = [regex]::Matches($testOutput, '(?m)^[ \t]+run\s+"[^"]+"\.\.\.\s+pass\s*$').Count
    if ($LASTEXITCODE -or $summaryCount -ne 1 -or $runPassCount -ne 5) { throw "contract tests failed or were not discovered" }
    Remove-Item $testDir -Recurse -Force

    & terraform "-chdir=$workRoot" apply -auto-approve -input=false -no-color -var "run_id=$runId" | Out-Null
    if ($LASTEXITCODE) { throw "LocalStack apply failed" }
    & terraform "-chdir=$workRoot" plan -detailed-exitcode -input=false -no-color -var "run_id=$runId" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Repeated plan is not empty" }
} catch {
    $failure = $_
} finally {
    if ((Test-Path $workRoot) -and (Test-Path (Join-Path $workRoot "terraform.tfstate"))) {
        & terraform "-chdir=$workRoot" destroy -auto-approve -input=false -no-color -var "run_id=$runId" | Out-Null
        if ($LASTEXITCODE -and -not $failure) { $failure = "LocalStack destroy failed" }
    }
    $resolved = [IO.Path]::GetFullPath($temp)
    if ($resolved.StartsWith([IO.Path]::GetFullPath($tempBase), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf).StartsWith("tfpro-c29-")) {
        Remove-Item $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if ($failure) { throw $failure }
Write-Host "PASS: Challenge 29 nested provider contracts and LocalStack replication E2E verified."
