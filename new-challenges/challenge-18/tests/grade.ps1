param(
    [string]$CandidateRoot
)

$ErrorActionPreference = "Stop"
$ChallengeRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $CandidateRoot) {
    $CandidateRoot = Join-Path $ChallengeRoot "starter"
}
elseif (-not [System.IO.Path]::IsPathRooted($CandidateRoot)) {
    $CandidateRoot = Join-Path $ChallengeRoot $CandidateRoot
}
$CandidateRoot = (Resolve-Path $CandidateRoot).Path

$tfText = Get-ChildItem -Path $CandidateRoot -Recurse -Filter "*.tf" -File |
    ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }
$allTfText = $tfText -join "`n"
$credentialAssignments = [regex]::Matches($allTfText, '(?m)^\s*(access_key|secret_key)\s*=\s*"([^"]+)"')
if ($credentialAssignments.Count -ne 8 -or @($credentialAssignments | Where-Object { $_.Groups[2].Value -ne "test" }).Count -gt 0) {
    throw "All four LocalStack provider configurations must use only test/test credentials."
}
if ($allTfText -notmatch "localstack_endpoint" -or $allTfText -notmatch "skip_credentials_validation") {
    throw "All AWS roots must use the configurable LocalStack provider contract."
}

$foundationMain = Get-Content -Raw -LiteralPath (Join-Path $CandidateRoot "foundation/main.tf")
$workloadMain = Get-Content -Raw -LiteralPath (Join-Path $CandidateRoot "workload/main.tf")
if ($foundationMain -notmatch '(?s)resource\s+"aws_vpc"\s+"dr".*?provider\s*=\s*aws\.dr' -or
    $foundationMain -notmatch '(?s)resource\s+"aws_subnet"\s+"dr".*?provider\s*=\s*aws\.dr') {
    throw "Foundation DR resources must explicitly use aws.dr."
}
if ($workloadMain -notmatch '(?s)module\s+"service_dr".*?providers\s*=\s*\{.*?aws\s*=\s*aws\.dr') {
    throw "The DR service module must explicitly map aws.dr."
}

$roots = @(
    @{ Name = "foundation"; Test = "foundation.tftest.hcl" },
    @{ Name = "workload"; Test = "workload.tftest.hcl" }
)

foreach ($item in $roots) {
    $root = Join-Path $CandidateRoot $item.Name
    $testDir = Join-Path $root "tests-generated"
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $item.Test) -Destination $testDir -Force
    try {
        & terraform "-chdir=$root" fmt -check -recursive
        if ($LASTEXITCODE -ne 0) { throw "terraform fmt failed for $($item.Name)" }
        & terraform "-chdir=$root" init -backend=false -input=false
        if ($LASTEXITCODE -ne 0) { throw "terraform init failed for $($item.Name)" }
        & terraform "-chdir=$root" validate
        if ($LASTEXITCODE -ne 0) { throw "terraform validate failed for $($item.Name)" }
        & terraform "-chdir=$root" test -test-directory=tests-generated
        if ($LASTEXITCODE -ne 0) { throw "terraform test failed for $($item.Name)" }
    }
    finally {
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $testDir
    }
}

Write-Host "PASS: Challenge 18 contract, provider graph, and deterministic outputs verified."
