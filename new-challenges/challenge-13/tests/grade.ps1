param(
    [string]$Candidate = (Join-Path $PSScriptRoot "../starter")
)

$ErrorActionPreference = "Stop"
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$generatedTests = Join-Path $candidatePath "tests-generated"

function Invoke-Terraform {
    param([string[]]$Arguments)
    & terraform "-chdir=$candidatePath" @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "terraform -chdir=$candidatePath $($Arguments -join ' ') exited $LASTEXITCODE"
    }
}

try {
    if (Test-Path -LiteralPath $generatedTests) {
        throw "reserved grader path already exists: $generatedTests"
    }
    New-Item -ItemType Directory -Path $generatedTests | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "contracts.tftest.hcl") -Destination $generatedTests

    Invoke-Terraform @("fmt", "-check", "-recursive", "-no-color")
    Invoke-Terraform @("init", "-backend=false", "-input=false", "-no-color")
    Invoke-Terraform @("validate", "-no-color")
    Invoke-Terraform @("test", "-test-directory=tests-generated", "-no-color")

    $configText = (Get-ChildItem -LiteralPath $candidatePath -Filter "*.tf" | Get-Content -Raw) -join "`n"
    if ($configText -notmatch 'output\s+"deployment_tokens"[\s\S]*?sensitive\s*=\s*true') {
        throw "deployment_tokens output must be explicitly sensitive"
    }
    Write-Host "PASS: complex types, deterministic dynamic instances, layered contracts, checks, and sensitive output verified"
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $generatedTests -ErrorAction SilentlyContinue
}
