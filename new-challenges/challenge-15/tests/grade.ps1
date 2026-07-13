param(
    [string]$Root = (Join-Path (Split-Path $PSScriptRoot -Parent) "starter")
)

$ErrorActionPreference = "Stop"
$ChallengeRoot = (Resolve-Path -LiteralPath (Split-Path $PSScriptRoot -Parent)).Path
$CandidateRoot = (Resolve-Path -LiteralPath $Root).Path
$TemporaryBase = [System.IO.Path]::GetTempPath()
$TemporaryRoot = Join-Path $TemporaryBase ("terraform-pro-c15-" + [guid]::NewGuid().ToString("N"))
$Workspace = Join-Path $TemporaryRoot "workspace"
$FixtureCopy = Join-Path $TemporaryRoot "fixtures"
$GeneratedTests = Join-Path $Workspace "tests-generated"

$providerText = Get-Content -Raw -LiteralPath (Join-Path $CandidateRoot "main.tf")
if ($providerText -notmatch 'access_key\s*=\s*"test"' -or
    $providerText -notmatch 'secret_key\s*=\s*"test"' -or
    $providerText -notmatch 'ec2\s*=\s*var\.localstack_endpoint') {
    throw "The AWS provider must use LocalStack test credentials and the configurable EC2 endpoint."
}

try {
    New-Item -ItemType Directory -Path $Workspace, $FixtureCopy, $GeneratedTests -Force | Out-Null
    Copy-Item -Path (Join-Path $CandidateRoot "*.tf") -Destination $Workspace -Force
    Copy-Item -Path (Join-Path $ChallengeRoot "fixtures\*") -Destination $FixtureCopy -Recurse -Force
    Copy-Item -Path (Join-Path $ChallengeRoot "tests\*.tftest.hcl") -Destination $GeneratedTests -Force

    & terraform "-chdir=$Workspace" init -backend=false -input=false -no-color
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed." }

    & terraform "-chdir=$Workspace" validate -no-color
    if ($LASTEXITCODE -ne 0) { throw "terraform validate failed." }

    & terraform "-chdir=$Workspace" test -test-directory=tests-generated -no-color
    if ($LASTEXITCODE -ne 0) { throw "Terraform mock tests failed." }

    Write-Host "PASS: CSV filtering, stable identities, grouping, and mocked AWS data sources verified."
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($TemporaryRoot)
    $resolvedTemporaryBase = [System.IO.Path]::GetFullPath($TemporaryBase)
    if ($resolvedTemporaryRoot.StartsWith($resolvedTemporaryBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedTemporaryRoot -Leaf).StartsWith("terraform-pro-c15-")) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
