param(
    [string]$Root = (Join-Path (Split-Path $PSScriptRoot -Parent) "starter")
)

$ErrorActionPreference = "Stop"
$ChallengeRoot = (Resolve-Path -LiteralPath (Split-Path $PSScriptRoot -Parent)).Path
$CandidateRoot = (Resolve-Path -LiteralPath $Root).Path
$TemporaryBase = [System.IO.Path]::GetTempPath()
$TemporaryRoot = Join-Path $TemporaryBase ("terraform-pro-c16-" + [guid]::NewGuid().ToString("N"))
$Workspace = Join-Path $TemporaryRoot "workspace"
$FixtureCopy = Join-Path $TemporaryRoot "fixtures"
$GeneratedTests = Join-Path $Workspace "tests-generated"

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

try {
    New-Item -ItemType Directory -Path $Workspace, $FixtureCopy, $GeneratedTests -Force | Out-Null
    Copy-Item -Path (Join-Path $CandidateRoot "*.tf") -Destination $Workspace -Force
    Copy-Item -Path (Join-Path $CandidateRoot "scripts") -Destination $Workspace -Recurse -Force
    Copy-Item -Path (Join-Path $ChallengeRoot "fixtures\*") -Destination $FixtureCopy -Recurse -Force
    Copy-Item -Path (Join-Path $ChallengeRoot "tests\*.tftest.hcl") -Destination $GeneratedTests -Force

    & terraform "-chdir=$Workspace" init -backend=false -input=false -no-color
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed." }

    & terraform "-chdir=$Workspace" validate -no-color
    if ($LASTEXITCODE -ne 0) { throw "terraform validate failed." }

    & terraform "-chdir=$Workspace" test -test-directory=tests-generated -no-color
    if ($LASTEXITCODE -ne 0) { throw "Terraform configuration tests failed." }

    $operator = Join-Path $Workspace "scripts\operate.ps1"
    if (-not (Test-Path -LiteralPath $operator)) {
        throw "Candidate is missing scripts/operate.ps1."
    }

    & pwsh -NoProfile -File $operator -Workspace $Workspace
    if ($LASTEXITCODE -ne 0) {
        throw "operate.ps1 returned exit code $LASTEXITCODE."
    }

    $evidencePath = Join-Path $Workspace ".automation\evidence.json"
    if (-not (Test-Path -LiteralPath $evidencePath)) {
        throw "operate.ps1 did not create .automation/evidence.json."
    }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json

    Assert-Equal $evidence.first_plan_exit 2 "Initial detailed-exitcode contract failed."
    Assert-Equal $evidence.first_plan_saved $true "Initial plan was not saved."
    Assert-Equal $evidence.json_audit_passed $true "Initial JSON audit was not recorded."
    Assert-Equal $evidence.create_count 3 "Unexpected create count."
    Assert-Equal $evidence.clean_plan_exit 0 "Saved plan apply did not lead to a clean plan."
    if ($evidence.state_backup_bytes -le 0) { throw "State backup is empty." }
    Assert-Equal $evidence.state_removed $true "Recovery simulation did not remove state."
    Assert-Equal $evidence.state_restored $true "State was not restored from backup."
    Assert-Equal $evidence.refresh_only_exit 2 "refresh-only did not report drift."
    Assert-Equal $evidence.drift_detected $true "Drift evidence is missing."
    Assert-Equal $evidence.repair_plan_exit 2 "Repair plan did not report changes."
    Assert-Equal $evidence.repair_audit_passed $true "Repair plan was not audited."
    Assert-Equal $evidence.final_plan_exit 0 "Final plan is not clean."

    $inventoryPath = Join-Path $Workspace "generated-inventory.json"
    $inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
    $serviceNames = @($inventory.services.PSObject.Properties.Name | Sort-Object)
    if (($serviceNames -join ",") -ne "api,worker") {
        throw "Repaired inventory has unexpected services: $($serviceNames -join ', ')."
    }

    $stateAddresses = @(& terraform "-chdir=$Workspace" state list)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect final state." }
    foreach ($address in @('terraform_data.service["api"]', 'terraform_data.service["worker"]', "local_file.inventory")) {
        if ($stateAddresses -notcontains $address) {
            throw "Final state is missing $address."
        }
    }

    Write-Host "PASS: saved plan, JSON audit, state recovery, refresh-only drift, and repair verified."
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($TemporaryRoot)
    $resolvedTemporaryBase = [System.IO.Path]::GetFullPath($TemporaryBase)
    if ($resolvedTemporaryRoot.StartsWith($resolvedTemporaryBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedTemporaryRoot -Leaf).StartsWith("terraform-pro-c16-")) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
