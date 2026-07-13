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

if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item -Path (Join-Path $legacy "*") -Destination $work -Recurse -Force

try {
    Push-Location $work
    Invoke-Terraform init -input=false -no-color
    Invoke-Terraform apply -auto-approve -input=false -no-color

    Get-ChildItem -Path $work -Filter "*.tf" | Remove-Item -Force
    Copy-Item -Path (Join-Path $candidate "*") -Destination $work -Recurse -Force
    Invoke-Terraform init -input=false -no-color

    & terraform plan -input=false -no-color "-out=migration.tfplan"
    if ($LASTEXITCODE -ne 0) { throw "Migration plan failed" }
    & terraform show -json migration.tfplan | Set-Content -LiteralPath migration.json
    if ($LASTEXITCODE -ne 0) { throw "Could not render migration plan as JSON" }
    $plan = Get-Content -Raw migration.json | ConvertFrom-Json -Depth 100
    $resourceChanges = @($plan.resource_changes)
    if ($resourceChanges.Count -ne 3) {
        throw "Expected exactly three migrated resources, found $($resourceChanges.Count)"
    }
    $nonNoOp = @($resourceChanges | Where-Object {
        $_.change.actions.Count -ne 1 -or $_.change.actions[0] -ne "no-op"
    })
    if ($nonNoOp.Count -gt 0) {
        throw "Migration contains create/update/delete actions: $($nonNoOp.address -join ', ')"
    }
    $withoutPreviousAddress = @($resourceChanges | Where-Object { -not $_.previous_address })
    if ($withoutPreviousAddress.Count -gt 0) {
        throw "Every resource must be represented by an explicit moved block"
    }

    Invoke-Terraform apply -input=false -no-color migration.tfplan

    $state = @(terraform state list)
    $expected = @(
        'module.service["api"].terraform_data.this',
        'module.service["web"].terraform_data.this',
        'module.service["worker"].terraform_data.this'
    )
    if (Compare-Object $expected $state) {
        throw "Final state addresses differ from the required module contract: $($state -join ', ')"
    }

    & terraform plan -detailed-exitcode -input=false -no-color | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Post-migration plan is not empty" }

    $localTests = Join-Path $work "tests-generated"
    New-Item -ItemType Directory -Path $localTests | Out-Null
    Copy-Item -Path (Join-Path $challengeRoot "tests/*.tftest.hcl") -Destination $localTests -Force
    Invoke-Terraform test "-test-directory=tests-generated" -no-color
}
finally {
    if ((Get-Location).Path -eq $work) { Pop-Location }
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

Write-Host "PASS: count-to-for_each module migration has no resource actions and final state is idempotent"
