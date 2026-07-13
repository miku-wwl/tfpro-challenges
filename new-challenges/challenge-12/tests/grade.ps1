param(
    [string]$Candidate = (Join-Path $PSScriptRoot "../starter")
)

$ErrorActionPreference = "Stop"
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$labRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tfpro-ch12-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $tempRoot "work"
$stateRoot = Join-Path $tempRoot "state"
$legacyState = Join-Path $stateRoot "legacy-producer.tfstate"
$producerState = Join-Path $stateRoot "central-producer.tfstate"
$consumerState = Join-Path $stateRoot "central-consumer.tfstate"

function Invoke-Terraform {
    param([string]$Root, [string[]]$Arguments, [int[]]$Expected = @(0))
    & terraform "-chdir=$Root" @Arguments
    if ($LASTEXITCODE -notin $Expected) {
        throw "terraform -chdir=$Root $($Arguments -join ' ') exited $LASTEXITCODE"
    }
    return $LASTEXITCODE
}

try {
    New-Item -ItemType Directory -Force -Path $workRoot, $stateRoot | Out-Null
    Get-ChildItem -Force -LiteralPath $candidatePath | Copy-Item -Recurse -Destination $workRoot
    Copy-Item -Recurse -LiteralPath (Join-Path $labRoot "fixtures") -Destination (Join-Path $tempRoot "fixtures")

    $producer = Join-Path $workRoot "producer"
    $consumer = Join-Path $workRoot "consumer"

    Invoke-Terraform $producer @("fmt", "-check", "-recursive", "-no-color") | Out-Null
    Invoke-Terraform $consumer @("fmt", "-check", "-recursive", "-no-color") | Out-Null

    # Create the legacy state through Terraform, then migrate it through the backend protocol.
    Invoke-Terraform $producer @("init", "-reconfigure", "-backend-config=path=$legacyState", "-input=false", "-no-color") | Out-Null
    Invoke-Terraform $producer @("validate", "-no-color") | Out-Null
    Invoke-Terraform $producer @("apply", "-auto-approve", "-input=false", "-no-color") | Out-Null
    $before = (& terraform "-chdir=$producer" show -json | ConvertFrom-Json)
    $beforeIds = @($before.values.root_module.resources | Sort-Object address | ForEach-Object { "$($_.address)=$($_.values.id)" })
    if ($beforeIds.Count -ne 2) { throw "producer must own exactly two stable network resources" }

    Invoke-Terraform $producer @("init", "-migrate-state", "-force-copy", "-backend-config=path=$producerState", "-input=false", "-no-color") | Out-Null
    if (-not (Test-Path -LiteralPath $producerState)) { throw "central producer state was not created" }
    $after = (& terraform "-chdir=$producer" show -json | ConvertFrom-Json)
    $afterIds = @($after.values.root_module.resources | Sort-Object address | ForEach-Object { "$($_.address)=$($_.values.id)" })
    if (Compare-Object $beforeIds $afterIds) { throw "producer identities changed during backend migration" }

    # Remove the legacy file so a copied state cannot accidentally satisfy the consumer.
    Remove-Item -Force -LiteralPath $legacyState -ErrorAction SilentlyContinue

    # Introduce a producer change after migration. Reversed automation would leave the
    # consumer without the new orders service and therefore fail the behavioral checks.
    Copy-Item -Force -LiteralPath (Join-Path $labRoot "fixtures/services-updated.csv") -Destination (Join-Path $tempRoot "fixtures/services.csv")

    $deploy = Join-Path $workRoot "automation/deploy.ps1"
    & pwsh -NoProfile -File $deploy -WorkRoot $workRoot -ProducerState $producerState -ConsumerState $consumerState
    if ($LASTEXITCODE -ne 0) { throw "ordered deployment automation failed" }

    foreach ($planFile in @("artifacts/producer.tfplan", "artifacts/consumer.tfplan")) {
        if (-not (Test-Path -LiteralPath (Join-Path $workRoot $planFile))) { throw "missing saved plan: $planFile" }
    }

    $producerAddresses = @(& terraform "-chdir=$producer" state list)
    $consumerAddresses = @(& terraform "-chdir=$consumer" state list | Where-Object { $_ -notmatch '^data\.' })
    if ((Compare-Object @('terraform_data.network["catalog"]', 'terraform_data.network["orders"]', 'terraform_data.network["payments"]') $producerAddresses)) {
        throw "producer state addresses are not the required stable service keys"
    }
    if ((Compare-Object @('terraform_data.application["catalog"]', 'terraform_data.application["orders"]', 'terraform_data.application["payments"]') $consumerAddresses)) {
        throw "consumer state ownership or stable keys are incorrect"
    }

    $manifest = (& terraform "-chdir=$consumer" output -json deployment_manifest | ConvertFrom-Json)
    if ($manifest.catalog.subnet_cidr -ne "10.42.10.0/24" -or $manifest.orders.subnet_cidr -ne "10.42.15.0/24" -or $manifest.payments.subnet_cidr -ne "10.42.20.0/24") {
        throw "consumer did not consume the producer contract"
    }

    $finalProducer = (& terraform "-chdir=$producer" show -json | ConvertFrom-Json)
    $preservedIds = @($finalProducer.values.root_module.resources | Where-Object { $_.address -notmatch 'orders' } | Sort-Object address | ForEach-Object { "$($_.address)=$($_.values.id)" })
    if (Compare-Object $beforeIds $preservedIds) { throw "existing producer identities changed after ordered deployment" }

    Invoke-Terraform $producer @("validate", "-no-color") | Out-Null
    Invoke-Terraform $consumer @("validate", "-no-color") | Out-Null

    Invoke-Terraform $producer @("plan", "-detailed-exitcode", "-input=false", "-no-color") @(0) | Out-Null
    Invoke-Terraform $consumer @("plan", "-detailed-exitcode", "-var=producer_state_path=$producerState", "-input=false", "-no-color") @(0) | Out-Null
    Write-Host "PASS: backend migration, state ownership, remote-state contract, ordered saved-plan automation, and empty plans verified"
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $tempRoot -ErrorAction SilentlyContinue
}
