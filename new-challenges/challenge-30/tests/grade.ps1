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

function Get-HclBlocks([string]$Text, [string]$HeaderPattern) {
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

function Assert-ExactAssignment([string]$Block, [string]$Name, [string]$ExpectedPattern, [string]$Context) {
    $assignments = @([regex]::Matches($Block, '(?m)^[ \t]*' + [regex]::Escape($Name) + '\s*=\s*(?<value>[^\r\n]+?)\s*$'))
    if ($assignments.Count -ne 1 -or $assignments[0].Groups['value'].Value.Trim() -notmatch ('^(?:' + $ExpectedPattern + ')$')) {
        throw "$Context must set $Name exactly once to the required safe value."
    }
}

function Assert-AwsProviderPair([string]$Source, [string[]]$Services, [bool]$RequirePathStyle, [string]$Context) {
    $blocks = @(Get-HclBlocks $Source '(?m)^[ \t]*provider\s+"aws"\s*\{')
    if ($blocks.Count -ne 2) { throw "$Context must contain exactly two AWS provider blocks." }
    $defaultBlocks = @($blocks | Where-Object { $_ -notmatch '(?m)^[ \t]*alias\s*=' })
    $drBlocks = @($blocks | Where-Object { [regex]::Matches($_, '(?m)^[ \t]*alias\s*=\s*"dr"\s*$').Count -eq 1 })
    if ($defaultBlocks.Count -ne 1 -or $drBlocks.Count -ne 1) {
        throw "$Context must contain exactly one default provider and one alias dr provider."
    }
    $pairs = @(
        @{ Block = $defaultBlocks[0]; Region = 'var\.primary_region'; Name = "$Context default provider" },
        @{ Block = $drBlocks[0]; Region = 'var\.dr_region'; Name = "$Context dr provider" }
    )
    foreach ($pair in $pairs) {
        Assert-ExactAssignment $pair.Block 'region' $pair.Region $pair.Name
        Assert-ExactAssignment $pair.Block 'access_key' '"test"' $pair.Name
        Assert-ExactAssignment $pair.Block 'secret_key' '"test"' $pair.Name
        foreach ($flag in @('skip_credentials_validation', 'skip_metadata_api_check', 'skip_requesting_account_id')) {
            Assert-ExactAssignment $pair.Block $flag 'true' $pair.Name
        }
        foreach ($service in $Services) {
            Assert-ExactAssignment $pair.Block $service 'var\.localstack_endpoint' $pair.Name
        }
        if ($RequirePathStyle) { Assert-ExactAssignment $pair.Block 's3_use_path_style' 'true' $pair.Name }
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
$allTf = (Get-ChildItem $CandidateRoot -Recurse -Filter *.tf -File | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$safeTf = Remove-HclComments $allTf
if ([regex]::Matches($safeTf, 'default\s*=\s*"http://(localhost|127\.0\.0\.1):4566"').Count -ne 3) {
    throw "Every root must default to the loopback LocalStack edge endpoint."
}

$foundationRoot = Join-Path $CandidateRoot "foundation"
$platformRoot = Join-Path $CandidateRoot "platform"
$workloadsRoot = Join-Path $CandidateRoot "workloads"
$foundationSource = Remove-HclComments (((Get-ChildItem $foundationRoot -File -Filter "*.tf") | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n")
$platformSource = Remove-HclComments (((Get-ChildItem $platformRoot -File -Filter "*.tf") | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n")
$workloadsSource = Remove-HclComments (((Get-ChildItem $workloadsRoot -File -Filter "*.tf") | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n")
Assert-AwsProviderPair $foundationSource @('ec2', 'sts') $false 'foundation root'
Assert-AwsProviderPair $platformSource @('ec2', 'sns', 'dynamodb', 'sts') $false 'platform root'
Assert-AwsProviderPair $workloadsSource @('s3', 'sts') $true 'workloads root'

$foundationMain = Remove-HclComments (Get-Content -Raw (Join-Path $foundationRoot "main.tf"))
$platformMain = Remove-HclComments (Get-Content -Raw (Join-Path $platformRoot "main.tf"))
$workloadsMain = Remove-HclComments (Get-Content -Raw (Join-Path $workloadsRoot "main.tf"))
$regionalMain = Remove-HclComments (Get-Content -Raw (Join-Path $CandidateRoot "workloads/modules/regional/main.tf"))
$drVpc = Get-HclBlockBody $foundationMain "resource" "aws_vpc" "dr"
$drSubnet = Get-HclBlockBody $foundationMain "resource" "aws_subnet" "dr"
if ($drVpc -notmatch '(?m)^[ \t]*provider\s*=\s*aws\.dr\s*$' -or
    $drSubnet -notmatch '(?m)^[ \t]*provider\s*=\s*aws\.dr\s*$') {
    throw "Both DR foundation resources must use aws.dr."
}
foreach ($resource in @("aws_security_group", "aws_sns_topic", "aws_dynamodb_table")) {
    $body = Get-HclBlockBody $platformMain "resource" $resource "dr"
    if ($body -notmatch '(?m)^[ \t]*provider\s*=\s*aws\.dr\s*$') {
        throw "The DR $resource must use aws.dr."
    }
}
$drModule = Get-HclBlockBody $workloadsMain "module" "dr"
if ($workloadsMain -notmatch '(?s)"\$\{name\}@\$\{location\}"' -or
    $drModule -notmatch '(?m)^[ \t]*providers\s*=\s*\{\s*aws\s*=\s*aws\.dr\s*\}') {
    throw "Workloads need stable name@location keys and explicit DR provider routing."
}
if ($regionalMain -notmatch '(?s)jsonencode\s*\(\s*\{.*?network\s*=\s*var\.network_contract.*?platform\s*=\s*var\.platform_contract') {
    throw "Each manifest must encode both upstream contracts."
}

$health = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -TimeoutSec 5
foreach ($service in @("ec2", "s3", "sns", "dynamodb", "sts")) {
    if ($health.services.$service -notin @("available", "running")) { throw "LocalStack $service is unavailable." }
}

$tempBase = [IO.Path]::GetTempPath()
$temp = Join-Path $tempBase ("tfpro-c30-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $temp "candidate"
$foundation = Join-Path $workRoot "foundation"
$platform = Join-Path $workRoot "platform"
$workloads = Join-Path $workRoot "workloads"
$runId = "c30" + [guid]::NewGuid().ToString("N").Substring(0, 10)
$failure = $null
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    Copy-CleanTree $CandidateRoot $workRoot
    Copy-CleanTree (Join-Path $LabRoot "fixtures") (Join-Path $temp "fixtures")

    $testCases = @(
        @{ Root = $foundation; Test = "foundation.tftest.hcl"; Passed = 2 },
        @{ Root = $platform; Test = "platform.tftest.hcl"; Passed = 3 },
        @{ Root = $workloads; Test = "workloads.tftest.hcl"; Passed = 7 }
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

    foreach ($root in @($foundation, $platform, $workloads)) {
        & terraform "-chdir=$root" apply -auto-approve -input=false -no-color -var "run_id=$runId" | Out-Null
        if ($LASTEXITCODE) { throw "E2E apply failed for $root" }
    }
    foreach ($root in @($foundation, $platform, $workloads)) {
        & terraform "-chdir=$root" plan -detailed-exitcode -input=false -no-color -var "run_id=$runId" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Repeated plan is not empty for $root" }
    }
} catch {
    $failure = $_
} finally {
    foreach ($root in @($workloads, $platform, $foundation)) {
        if ((Test-Path $root) -and (Test-Path (Join-Path $root "terraform.tfstate"))) {
            & terraform "-chdir=$root" destroy -auto-approve -input=false -no-color -var "run_id=$runId" | Out-Null
            if ($LASTEXITCODE -and -not $failure) { $failure = "E2E destroy failed for $root" }
        }
    }
    $resolved = [IO.Path]::GetFullPath($temp)
    if ($resolved.StartsWith([IO.Path]::GetFullPath($tempBase), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf).StartsWith("tfpro-c30-")) {
        Remove-Item $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if ($failure) { throw $failure }
Write-Host "PASS: Challenge 30 mock contracts and LocalStack three-state E2E verified."
