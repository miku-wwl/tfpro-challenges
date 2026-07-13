param(
    [string]$Candidate = (Join-Path $PSScriptRoot "../starter")
)

$ErrorActionPreference = "Stop"
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$labRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$generatedTests = Join-Path $candidatePath "tests-generated"

function Invoke-Terraform {
    param([string]$Root, [string[]]$Arguments, [int[]]$Expected = @(0))
    & terraform "-chdir=$Root" @Arguments
    if ($LASTEXITCODE -notin $Expected) {
        throw "terraform -chdir=$Root $($Arguments -join ' ') exited $LASTEXITCODE"
    }
    return $LASTEXITCODE
}

if (Test-Path -LiteralPath $generatedTests) { throw "reserved grader path already exists: $generatedTests" }
New-Item -ItemType Directory -Path $generatedTests | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "upgrade.tftest.hcl") -Destination $generatedTests

try {
    Invoke-Terraform $candidatePath @("fmt", "-check", "-recursive", "-no-color") | Out-Null
    Invoke-Terraform $candidatePath @("init", "-upgrade", "-backend=false", "-input=false", "-no-color") | Out-Null
    Invoke-Terraform $candidatePath @("validate", "-no-color") | Out-Null
    Invoke-Terraform $candidatePath @("test", "-test-directory=tests-generated", "-no-color") | Out-Null
    Invoke-Terraform $candidatePath @("init", "-lockfile=readonly", "-backend=false", "-input=false", "-no-color") | Out-Null

$lockPath = Join-Path $candidatePath ".terraform.lock.hcl"
if (-not (Test-Path -LiteralPath $lockPath)) { throw "dependency lockfile is missing" }
$lockText = Get-Content -Raw -LiteralPath $lockPath
if ($lockText -notmatch 'provider "registry\.terraform\.io/hashicorp/random"' -or $lockText -notmatch 'version\s*=\s*"3\.7\.[0-9]+"') {
    throw "lockfile must select a Random provider 3.7.x release"
}
if (($lockText | Select-String -Pattern 'h1:|zh:' -AllMatches).Matches.Count -lt 1) {
    throw "lockfile is missing provider package checksums"
}

$providers = (& terraform "-chdir=$candidatePath" providers | Out-String)
if ($LASTEXITCODE -ne 0 -or $providers -notmatch '~> 3\.7\.0' -or $providers -notmatch '>= 3\.7\.0') {
    throw "root and child provider requirements were not both visible"
}

$diagnosis = Get-Content -Raw -LiteralPath (Join-Path $candidatePath "DIAGNOSIS.md")
foreach ($marker in @("ROOT_CHILD_CONSTRAINT_INTERSECTION", "LOCKFILE_SELECTION_CONFLICT", "MODULE_API_V2")) {
    $markerIndex = $diagnosis.IndexOf($marker)
    if ($markerIndex -lt 0) { throw "DIAGNOSIS.md is missing $marker" }
    $sectionStart = [Math]::Max(0, $markerIndex - 500)
    if ($diagnosis.Substring($sectionStart, $markerIndex - $sectionStart) -match '(?im)^TODO') {
        throw "DIAGNOSIS.md still contains an unfinished TODO near $marker"
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tfpro-ch14-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $conflict = Join-Path $tempRoot "provider-conflict"
    Copy-Item -Recurse -LiteralPath (Join-Path $labRoot "fixtures/failures/provider-conflict") -Destination $conflict
    $conflictLog = & terraform "-chdir=$conflict" init -backend=false -input=false -no-color 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $conflictLog -notmatch 'no available releases match|no available releases match the given constraints|Could not retrieve') {
        throw "provider-conflict fixture did not fail with an unsatisfiable selection"
    }

    $stale = Join-Path $tempRoot "stale-lock"
    Copy-Item -Recurse -LiteralPath (Join-Path $labRoot "fixtures/failures/stale-lock") -Destination $stale
    $staleLog = & terraform "-chdir=$stale" init -backend=false -lockfile=readonly -input=false -no-color 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $staleLog -notmatch 'locked provider|does not match configured version constraint|read-only') {
        throw "stale-lock fixture did not demonstrate the expected readonly lock conflict"
    }
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $tempRoot -ErrorAction SilentlyContinue
}

    Write-Host "PASS: constraints, provider upgrade, readonly lockfile, module v2 contract, and failure diagnosis verified"
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $generatedTests -ErrorAction SilentlyContinue
}
