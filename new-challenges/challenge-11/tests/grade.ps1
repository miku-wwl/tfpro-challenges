param(
    [string]$CandidateDir = "./starter"
)

$ErrorActionPreference = "Stop"

$challengeRoot = Split-Path -Parent $PSScriptRoot
$candidate = (Resolve-Path (Join-Path $challengeRoot $CandidateDir)).Path
$generatedTests = Join-Path $candidate "tests-generated"

function Invoke-Terraform {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & terraform @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "terraform $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

$tfFiles = Get-ChildItem -Path $candidate -Recurse -Filter "*.tf"
$providerText = Get-Content -Raw -LiteralPath (Join-Path $candidate "providers.tf")
$credentialAssignments = [regex]::Matches($providerText, '(?m)^\s*(access_key|secret_key)\s*=\s*"([^"]+)"')
if ($credentialAssignments.Count -ne 4 -or @($credentialAssignments | Where-Object { $_.Groups[2].Value -ne "test" }).Count -gt 0) {
    throw "Both LocalStack providers must use only the fixed test/test credentials."
}
foreach ($required in @("localstack_endpoint", "skip_credentials_validation", "skip_metadata_api_check", "skip_requesting_account_id")) {
    if ($providerText -notmatch [regex]::Escape($required)) {
        throw "LocalStack provider configuration is missing $required."
    }
}

$runbook = Join-Path $candidate "AUTH_RUNBOOK.md"
if (-not (Test-Path -LiteralPath $runbook)) { throw "AUTH_RUNBOOK.md is required" }
$runbookText = Get-Content -Raw $runbook
foreach ($requiredTerm in @("LocalStack", "endpoint", "provider", "secret")) {
    if ($runbookText -notmatch [regex]::Escape($requiredTerm)) {
        throw "AUTH_RUNBOOK.md must cover $requiredTerm"
    }
}
if ($runbookText -match "错误建议") {
    throw "Remove the unsafe starter recommendation from AUTH_RUNBOOK.md"
}

if (Test-Path -LiteralPath $generatedTests) { Remove-Item -LiteralPath $generatedTests -Recurse -Force }
New-Item -ItemType Directory -Path $generatedTests | Out-Null
Copy-Item -Path (Join-Path $challengeRoot "tests/*.tftest.hcl") -Destination $generatedTests -Force

try {
    Push-Location $candidate
    Invoke-Terraform init -input=false -no-color
    Invoke-Terraform validate -no-color
    Invoke-Terraform test "-test-directory=tests-generated" -no-color
}
finally {
    if ((Get-Location).Path -eq $candidate) { Pop-Location }
    if (Test-Path -LiteralPath $generatedTests) { Remove-Item -LiteralPath $generatedTests -Recurse -Force }
}

Write-Host "PASS: provider aliases, child mapping, caller identities, regions, and credential hygiene verified"
