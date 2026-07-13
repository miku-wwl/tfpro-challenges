param(
    [string]$CandidateDir = "./starter"
)

$ErrorActionPreference = "Stop"

$challengeRoot = Split-Path -Parent $PSScriptRoot
$candidate = (Resolve-Path (Join-Path $challengeRoot $CandidateDir)).Path
$legacy = Join-Path $challengeRoot "fixtures/legacy"
$work = Join-Path $challengeRoot ".grade-work"

function Invoke-Terraform {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & terraform @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "terraform $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

if (Test-Path -LiteralPath $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
}
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item -Path (Join-Path $legacy "*") -Destination $work -Recurse -Force

try {
    Push-Location $work
    Invoke-Terraform init -input=false -no-color
    Invoke-Terraform apply -auto-approve -input=false -no-color

    $legacyState = @(terraform state list)
    foreach ($address in @("terraform_data.workload[0]", "terraform_data.workload[1]", "terraform_data.workload[2]", "terraform_data.retired", "local_file.inventory")) {
        if ($legacyState -notcontains $address) { throw "Legacy state is missing $address" }
    }

    Invoke-Terraform state rm terraform_data.retired

    Get-ChildItem -Path $work -Filter "*.tf" | Remove-Item -Force
    Copy-Item -Path (Join-Path $candidate "*") -Destination $work -Recurse -Force
    Invoke-Terraform init -input=false -no-color

    & terraform plan -input=false -no-color "-out=migration.tfplan"
    if ($LASTEXITCODE -ne 0) { throw "Migration plan failed" }
    & terraform show -json migration.tfplan | Set-Content -LiteralPath migration.json
    $plan = Get-Content -Raw migration.json | ConvertFrom-Json -Depth 100
    $destructive = @($plan.resource_changes | Where-Object {
        $_.change.actions -contains "delete" -or $_.change.actions -contains "create"
    })
    $unexpected = @($destructive | Where-Object { $_.address -ne "terraform_data.guardian" })
    if ($unexpected.Count -gt 0) {
        throw "Migration would create/delete managed legacy objects: $($unexpected.address -join ', ')"
    }

    Invoke-Terraform apply -auto-approve -input=false -no-color migration.tfplan

    $state = @(terraform state list)
    $expected = @(
        "local_file.manifest",
        "terraform_data.guardian",
        'terraform_data.service["api"]',
        'terraform_data.service["web"]',
        'terraform_data.service["worker"]'
    )
    if (Compare-Object $expected $state) {
        throw "Final state addresses differ from the required contract: $($state -join ', ')"
    }

    $guardian = terraform state show -no-color terraform_data.guardian
    if (($guardian -join "`n") -notmatch 'id\s+=\s+"ops-guardian-v1"') {
        throw "Guardian was not imported with the required ID"
    }

    & terraform plan -detailed-exitcode -input=false -no-color | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Post-migration plan is not empty" }

    & terraform plan -input=false -no-color "-var=manifest_path=./generated/replacement.json" "-out=lifecycle.tfplan" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not generate lifecycle probe plan" }
    & terraform show -json lifecycle.tfplan | Set-Content -LiteralPath lifecycle.json
    $lifecyclePlan = Get-Content -Raw lifecycle.json | ConvertFrom-Json -Depth 100
    $manifestChange = $lifecyclePlan.resource_changes | Where-Object { $_.address -eq "local_file.manifest" }
    if (($manifestChange.change.actions -join ",") -ne "create,delete") {
        throw "Manifest replacement must use create_before_destroy"
    }

    $destroyProbe = (& terraform plan -destroy -input=false -no-color 2>&1) -join "`n"
    if ($LASTEXITCODE -eq 0 -or $destroyProbe -notmatch "prevent_destroy") {
        throw "Guardian must block destroy with prevent_destroy"
    }

    Pop-Location
    & (Join-Path $challengeRoot "fixtures/drift.ps1") -WorkDir $work
    Push-Location $work

    & terraform plan -detailed-exitcode -input=false -no-color | Out-Null
    if ($LASTEXITCODE -ne 2) { throw "Out-of-band manifest drift was not detected" }
    Invoke-Terraform apply -auto-approve -input=false -no-color
    & terraform plan -detailed-exitcode -input=false -no-color | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Final plan still contains changes" }

    $localTests = Join-Path $work "tests-generated"
    New-Item -ItemType Directory -Path $localTests | Out-Null
    Copy-Item -Path (Join-Path $challengeRoot "tests/*.tftest.hcl") -Destination $localTests -Force
    Invoke-Terraform test "-test-directory=tests-generated" -no-color
}
finally {
    if ((Get-Location).Path -eq $work) { Pop-Location }
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Write-Host "PASS: same-state import, moved addresses, state rm, drift recovery, and idempotence verified"
