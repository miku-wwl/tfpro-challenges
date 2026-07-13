param(
    [string]$Root = (Join-Path (Split-Path $PSScriptRoot -Parent) "starter")
)

$ErrorActionPreference = "Stop"
$ChallengeRoot = (Resolve-Path -LiteralPath (Split-Path $PSScriptRoot -Parent)).Path
$CandidateRoot = (Resolve-Path -LiteralPath $Root).Path
$TemporaryBase = [System.IO.Path]::GetTempPath()
$TemporaryRoot = Join-Path $TemporaryBase ("terraform-pro-c17-" + [guid]::NewGuid().ToString("N"))
$Workspace = Join-Path $TemporaryRoot "workspace"
$GeneratedTests = Join-Path $Workspace "tests-generated"

$providerText = Get-Content -Raw -LiteralPath (Join-Path $CandidateRoot "main.tf")
$credentialAssignments = [regex]::Matches($providerText, '(?m)^\s*(access_key|secret_key)\s*=\s*"([^"]+)"')
if ($credentialAssignments.Count -ne 4 -or @($credentialAssignments | Where-Object { $_.Groups[2].Value -ne "test" }).Count -gt 0) {
    throw "Both aliased providers must use only the fixed LocalStack test/test credentials."
}
foreach ($service in @("s3", "sns", "sts")) {
    if ($providerText -notmatch ("(?m)^\s*" + $service + "\s*=\s*var\.localstack_endpoint")) {
        throw "Both providers must route $service to localstack_endpoint."
    }
}

try {
    New-Item -ItemType Directory -Path $Workspace, $GeneratedTests -Force | Out-Null
    Copy-Item -Path (Join-Path $CandidateRoot "*.tf") -Destination $Workspace -Force
    Copy-Item -Path (Join-Path $CandidateRoot "modules") -Destination $Workspace -Recurse -Force
    Copy-Item -Path (Join-Path $ChallengeRoot "tests\*.tftest.hcl") -Destination $GeneratedTests -Force

    & terraform "-chdir=$Workspace" init -backend=false -input=false -no-color
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed." }

    & terraform "-chdir=$Workspace" validate -no-color
    if ($LASTEXITCODE -ne 0) { throw "terraform validate failed." }

    & terraform "-chdir=$Workspace" test -test-directory=tests-generated -no-color
    if ($LASTEXITCODE -ne 0) { throw "Terraform provider graph tests failed." }

    Write-Host "PASS: nested aliases, cross-module outputs, validation, and provider routing verified."
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($TemporaryRoot)
    $resolvedTemporaryBase = [System.IO.Path]::GetFullPath($TemporaryBase)
    if ($resolvedTemporaryRoot.StartsWith($resolvedTemporaryBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedTemporaryRoot -Leaf).StartsWith("terraform-pro-c17-")) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
