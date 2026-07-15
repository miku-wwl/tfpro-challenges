param(
    [string]$Candidate = '',
    [string]$LocalstackEndpoint = "http://localhost:4566",
    [switch]$UnitOnly
)

if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '../starter' }

function Assert-LoopbackEndpoint([string]$Endpoint) {
    $uri = $null
    if ([string]::IsNullOrEmpty($Endpoint) -or $Endpoint.IndexOf([char]13) -ge 0 -or $Endpoint.IndexOf([char]10) -ge 0) {
        throw 'LocalstackEndpoint contains CR/LF or is empty.'
    }
    $match = [regex]::Match($Endpoint, '\Ahttps?://(?:localhost|127\.0\.0\.1|\[::1\]):(?<port>[1-9][0-9]{0,4})\z', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if (-not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or
        -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
        $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or
        $uri.PathAndQuery -ne '/' -or -not [string]::IsNullOrEmpty($uri.UserInfo)) {
        throw 'LocalstackEndpoint must be an HTTP(S) loopback root origin with explicit port 1-65535.'
    }
}

Assert-LoopbackEndpoint $LocalstackEndpoint
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $File @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($code -notin $Allowed) {
        throw "$File $($Arguments -join ' ') failed with exit $code.`n$($lines -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ ExitCode = $code; Text = ($lines -join [Environment]::NewLine) }
}

function Invoke-Aws([string[]]$Arguments, [int[]]$Allowed = @(0)) {
    return Invoke-Native 'aws' (@('--endpoint-url', $LocalstackEndpoint) + $Arguments) $Allowed
}

function Copy-CleanTree([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup') -or
            $item.Extension -in @('.tfplan', '.tfstate')) {
            continue
        }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            Copy-CleanTree $item.FullName $target
        }
        else {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-PlanDocument([string]$WorkingDirectory, [string]$PlanPath, [string]$JsonPath) {
    $json = (Invoke-Native 'terraform' @("-chdir=$WorkingDirectory", 'show', '-json', $PlanPath)).Text
    Write-Utf8 $JsonPath $json
    return ($json | ConvertFrom-Json)
}

function Get-ManagedChanges($Document) {
    $changes = @()
    if ($null -eq $Document.PSObject.Properties['resource_changes']) { return @() }
    foreach ($change in @($Document.resource_changes)) {
        if ([string]$change.address -like 'data.*') { continue }
        $actions = @($change.change.actions)
        if (($actions -join ',') -ne 'no-op') { $changes += $change }
    }
    return @($changes)
}

function Assert-ExactManagedChanges($Document, [hashtable]$Expected, [string]$Label) {
    $actual = @{}
    foreach ($change in @(Get-ManagedChanges $Document)) {
        $address = [string]$change.address
        if ($actual.ContainsKey($address)) { throw "$Label contains duplicate change address $address." }
        $actual[$address] = (@($change.change.actions) -join ',')
    }
    if ($actual.Count -ne $Expected.Count) {
        throw "$Label expected $($Expected.Count) managed changes but found $($actual.Count): $($actual.Keys -join ', ')"
    }
    foreach ($address in $Expected.Keys) {
        if (-not $actual.ContainsKey($address) -or $actual[$address] -ne $Expected[$address]) {
            throw "$Label expected $address=$($Expected[$address]); actual=$($actual[$address])."
        }
    }
}

function Assert-ExactDrift($Document, [string[]]$Expected, [string]$Label) {
    $driftEntries = @()
    if ($null -ne $Document.PSObject.Properties['resource_drift']) { $driftEntries = @($Document.resource_drift) }
    $actual = @($driftEntries | ForEach-Object { [string]$_.address } | Sort-Object -Unique)
    $wanted = @($Expected | Sort-Object -Unique)
    if (($actual -join '|') -ne ($wanted -join '|')) {
        throw "$Label drift mismatch. Expected $($wanted -join ', '); actual $($actual -join ', ')."
    }
}

function Get-FileDigest([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-S3Object([string]$Bucket, [string]$Key, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
    Invoke-Aws @('s3api', 'get-object', '--bucket', $Bucket, '--key', $Key, $Destination) | Out-Null
    return [IO.File]::ReadAllText($Destination)
}

$terraformVersion = ((Invoke-Native 'terraform' @('version', '-json')).Text | ConvertFrom-Json).terraform_version
if ($terraformVersion -ne '1.6.6') { throw "Terraform 1.6.6 is required; active version is $terraformVersion." }
$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$fixturesPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../fixtures')).Path
$tfFiles = @(Get-ChildItem -LiteralPath $candidatePath -Filter '*.tf' -File)
if ($tfFiles.Count -lt 5) { throw 'Candidate must contain the complete Terraform HCL root.' }
$allTf = ($tfFiles | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
if ($allTf -match '(?i)TODO|incomplete|catalog_valid\s*=\s*false|value\s*=\s*null') {
    throw 'Candidate still contains unfinished starter markers.'
}
if (@(Get-ChildItem -LiteralPath $candidatePath -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.sh', '.py') }).Count -ne 0) {
    throw 'Candidate implementation must be Terraform HCL only; scripts are not accepted.'
}
if ($allTf -notmatch 'required_version\s*=\s*"~> 1\.6"' -or $allTf -notmatch 'version\s*=\s*"~> 5\.100"') {
    throw 'Exact Terraform and AWS provider constraints are required.'
}
$resourceTypes = @([regex]::Matches($allTf, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($resourceTypes -join ',') -ne 'aws_s3_bucket,aws_s3_object') {
    throw "Candidate resources must be exactly aws_s3_bucket and aws_s3_object; got $($resourceTypes -join ',')."
}
foreach ($token in @('jsondecode', 'for_each', 'source_hash', 'etag', 'precondition', 'semantic_fingerprint', 'aws_caller_identity')) {
    if ($allTf -notmatch [regex]::Escape($token)) { throw "Candidate does not implement required HCL concept: $token." }
}
if ($allTf -match '(?i)\bcount\s*=|ignore_changes|aws_sns_|mock_provider|override_(resource|data|module)|refresh\s*=\s*false') {
    throw 'Candidate uses a forbidden identity, drift-hiding, SNS, or post-1.6 testing feature.'
}
$canonicalText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'canonical.tftest.hcl'))
if ($canonicalText -match '(?i)mock_provider|override_(resource|data|module)' -or
    ([regex]::Matches($canonicalText, '(?m)^run\s+"')).Count -ne 8) {
    throw 'Canonical tests must have exactly 8 Terraform 1.6-compatible runs without mocks or overrides.'
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("tfpro-c46-grade-" + [Guid]::NewGuid().ToString('N'))
$work = Join-Path $tempRoot 'candidate'
$fixtureWork = Join-Path $tempRoot 'fixtures'
$pluginCache = Join-Path $tempRoot 'plugin-cache'
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED', 'AWS_PAGER', 'TF_PLUGIN_CACHE_DIR')) {
    $envBefore[$name] = [Environment]::GetEnvironmentVariable($name)
}
$runId = $null
$bucket = $null
$initialized = $false

try {
    $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health')
    foreach ($service in @('s3', 'sts')) {
        if ([string]$health.services.$service -notmatch 'available|running') { throw "LocalStack $service is unavailable." }
    }

    $env:AWS_ACCESS_KEY_ID = 'test'
    $env:AWS_SECRET_ACCESS_KEY = 'test'
    $env:AWS_DEFAULT_REGION = 'us-east-1'
    $env:AWS_EC2_METADATA_DISABLED = 'true'
    $env:AWS_PAGER = ''
    New-Item -ItemType Directory -Path $pluginCache -Force | Out-Null
    $env:TF_PLUGIN_CACHE_DIR = $pluginCache

    Copy-CleanTree $candidatePath $work
    Copy-CleanTree $fixturesPath $fixtureWork
    New-Item -ItemType Directory -Path (Join-Path $work 'tests') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $work 'tests/canonical.tftest.hcl') -Force

    Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $work) | Out-Null
    Invoke-Native 'terraform' @("-chdir=$work", 'init', '-backend=false', '-input=false') | Out-Null
    $initialized = $true
    Invoke-Native 'terraform' @("-chdir=$work", 'validate', '-no-color') | Out-Null
    $test = Invoke-Native 'terraform' @("-chdir=$work", 'test', '-test-directory=tests', '-no-color')
    if ($test.Text -notmatch 'Success! 8 passed, 0 failed') { throw "Canonical results mismatch.`n$($test.Text)" }
    Write-Host '[canonical] fmt/init/validate and 8 Terraform 1.6-compatible runs passed.'
    if ($UnitOnly) {
        Write-Host 'PASS challenge-46 UnitOnly'
        return
    }

    $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 10)
    $runId = "c46-$suffix"
    $bucket = "tfpro-c46-$runId"
    $v1Catalog = Join-Path $fixtureWork 'catalog-v1.json'
    $reorderedCatalog = Join-Path $fixtureWork 'catalog-v1-reordered.json'

    $v1Vars = Join-Path $tempRoot 'v1.tfvars.json'
    $reorderedVars = Join-Path $tempRoot 'reordered.tfvars.json'
    $v2Vars = Join-Path $tempRoot 'v2.tfvars.json'
    Write-Utf8 $v1Vars ([ordered]@{ run_id = $runId; localstack_endpoint = $LocalstackEndpoint; catalog_path = '../fixtures/catalog-v1.json' } | ConvertTo-Json)
    Write-Utf8 $reorderedVars ([ordered]@{ run_id = $runId; localstack_endpoint = $LocalstackEndpoint; catalog_path = '../fixtures/catalog-v1-reordered.json' } | ConvertTo-Json)
    Write-Utf8 $v2Vars ([ordered]@{ run_id = $runId; localstack_endpoint = $LocalstackEndpoint; catalog_path = '../fixtures/catalog-v2.json' } | ConvertTo-Json)

    Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-auto-approve', '-input=false', "-var-file=$v1Vars") | Out-Null
    $v1Contract = ((Invoke-Native 'terraform' @("-chdir=$work", 'output', '-json', 'release_contract')).Text | ConvertFrom-Json)
    if ($v1Contract.account_id -ne '000000000000' -or $v1Contract.release -ne 'v1' -or @($v1Contract.object_addresses).Count -ne 2) {
        throw 'Real v1 release contract is invalid.'
    }

    $clean = Invoke-Native 'terraform' @("-chdir=$work", 'plan', '-input=false', '-detailed-exitcode', "-var-file=$v1Vars") @(0, 2)
    if ($clean.ExitCode -ne 0) { throw 'The v1 configuration is not clean after apply.' }

    $reorderPlan = Join-Path $tempRoot 'reorder.tfplan'
    $reorder = Invoke-Native 'terraform' @("-chdir=$work", 'plan', '-input=false', '-detailed-exitcode', "-var-file=$reorderedVars", "-out=$reorderPlan") @(0, 2)
    if ($reorder.ExitCode -ne 0) { throw 'Reordering the JSON catalog must be a strict no-op.' }
    $reorderDoc = Get-PlanDocument $work $reorderPlan (Join-Path $tempRoot 'reorder.json')
    Assert-ExactManagedChanges $reorderDoc @{} 'Reordered catalog plan'
    $reorderedFingerprint = [string]$reorderDoc.planned_values.outputs.release_contract.value.semantic_fingerprint
    if ($reorderedFingerprint -ne [string]$v1Contract.semantic_fingerprint) { throw 'Catalog reordering changed the semantic fingerprint.' }

    $upgradePlan = Join-Path $tempRoot 'upgrade.tfplan'
    $upgrade = Invoke-Native 'terraform' @("-chdir=$work", 'plan', '-input=false', '-detailed-exitcode', "-var-file=$v2Vars", "-out=$upgradePlan") @(0, 2)
    if ($upgrade.ExitCode -ne 2) { throw 'The v1 to v2 release must produce detailed-exitcode 2.' }
    $upgradeDoc = Get-PlanDocument $work $upgradePlan (Join-Path $tempRoot 'upgrade.json')
    $expectedUpdates = @{
        'aws_s3_object.artifact["api"]' = 'update'
        'aws_s3_object.artifact["worker"]' = 'update'
    }
    Assert-ExactManagedChanges $upgradeDoc $expectedUpdates 'v2 saved plan'
    $auditedUpgradeDigest = Get-FileDigest $upgradePlan

    if ((Get-FileDigest $upgradePlan) -ne $auditedUpgradeDigest) { throw 'The audited saved plan artifact changed before apply.' }
    Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-auto-approve', '-input=false', $upgradePlan) | Out-Null

    $v2Contract = ((Invoke-Native 'terraform' @("-chdir=$work", 'output', '-json', 'release_contract')).Text | ConvertFrom-Json)
    if ($v2Contract.release -ne 'v2' -or
        [string]$v2Contract.artifacts.api.content_sha256 -ne [string]$upgradeDoc.planned_values.outputs.release_contract.value.artifacts.api.content_sha256) {
        throw 'Applying the audited saved plan did not retain its v2 artifact contract.'
    }
    if ((Read-S3Object $bucket 'releases/api.txt' (Join-Path $tempRoot 'api-v2.txt')) -ne 'api release payload v2' -or
        (Read-S3Object $bucket 'releases/worker.txt' (Join-Path $tempRoot 'worker-v2.txt')) -ne 'worker release payload v2') {
        throw 'Applying the audited saved plan did not publish its approved values.'
    }

    $postUpgradeClean = Invoke-Native 'terraform' @("-chdir=$work", 'plan', '-input=false', '-detailed-exitcode', "-var-file=$v2Vars") @(0, 2)
    if ($postUpgradeClean.ExitCode -ne 0) { throw 'The applied v2 saved plan is not clean.' }

    $driftBody = Join-Path $tempRoot 'manual-content.txt'
    Write-Utf8 $driftBody 'manual content drift'
    Invoke-Aws @('s3api', 'put-object', '--bucket', $bucket, '--key', 'releases/api.txt', '--body', $driftBody, '--content-type', 'text/plain') | Out-Null
    $driftTags = Join-Path $tempRoot 'manual-tags.json'
    Write-Utf8 $driftTags '{"TagSet":[{"Key":"Drift","Value":"manual"}]}'
    Invoke-Aws @('s3api', 'put-object-tagging', '--bucket', $bucket, '--key', 'releases/worker.txt', '--tagging', ('file://' + ($driftTags -replace '\\', '/'))) | Out-Null

    $refreshPlan = Join-Path $tempRoot 'refresh.tfplan'
    $refresh = Invoke-Native 'terraform' @("-chdir=$work", 'plan', '-refresh-only', '-input=false', '-detailed-exitcode', "-var-file=$v2Vars", "-out=$refreshPlan") @(0, 2)
    if ($refresh.ExitCode -ne 2) { throw 'Real object and tag drift must produce refresh-only detailed-exitcode 2.' }
    $refreshDoc = Get-PlanDocument $work $refreshPlan (Join-Path $tempRoot 'refresh.json')
    Assert-ExactDrift $refreshDoc @('aws_s3_object.artifact["api"]', 'aws_s3_object.artifact["worker"]') 'Refresh-only plan'
    Assert-ExactManagedChanges $refreshDoc @{} 'Refresh-only plan'
    $auditedRefreshDigest = Get-FileDigest $refreshPlan
    if ((Get-FileDigest $refreshPlan) -ne $auditedRefreshDigest) { throw 'Refresh-only plan changed after audit.' }
    Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-auto-approve', '-input=false', $refreshPlan) | Out-Null

    if ((Read-S3Object $bucket 'releases/api.txt' (Join-Path $tempRoot 'api-drift.txt')) -ne 'manual content drift') {
        throw 'Applying refresh-only unexpectedly repaired the remote object.'
    }
    $workerDriftTags = ((Invoke-Aws @('s3api', 'get-object-tagging', '--bucket', $bucket, '--key', 'releases/worker.txt', '--output', 'json')).Text | ConvertFrom-Json).TagSet
    if (@($workerDriftTags | Where-Object { $_.Key -eq 'Drift' -and $_.Value -eq 'manual' }).Count -ne 1) {
        throw 'Applying refresh-only unexpectedly repaired the remote tags.'
    }

    $repairPlan = Join-Path $tempRoot 'repair.tfplan'
    $repair = Invoke-Native 'terraform' @("-chdir=$work", 'plan', '-input=false', '-detailed-exitcode', "-var-file=$v2Vars", "-out=$repairPlan") @(0, 2)
    if ($repair.ExitCode -ne 2) { throw 'Configuration repair must produce detailed-exitcode 2.' }
    $repairDoc = Get-PlanDocument $work $repairPlan (Join-Path $tempRoot 'repair.json')
    Assert-ExactManagedChanges $repairDoc $expectedUpdates 'Repair saved plan'
    $auditedRepairDigest = Get-FileDigest $repairPlan
    if ((Get-FileDigest $repairPlan) -ne $auditedRepairDigest) { throw 'Repair plan changed after audit.' }
    Invoke-Native 'terraform' @("-chdir=$work", 'apply', '-auto-approve', '-input=false', $repairPlan) | Out-Null

    if ((Read-S3Object $bucket 'releases/api.txt' (Join-Path $tempRoot 'api-repaired.txt')) -ne 'api release payload v2') {
        throw 'Repair did not restore the approved API content.'
    }
    $workerTags = @(((Invoke-Aws @('s3api', 'get-object-tagging', '--bucket', $bucket, '--key', 'releases/worker.txt', '--output', 'json')).Text | ConvertFrom-Json).TagSet)
    $expectedTagKeys = @('Artifact', 'Challenge', 'ManagedBy', 'Release', 'RunId')
    $actualTagKeys = @($workerTags | ForEach-Object { [string]$_.Key } | Sort-Object)
    if (($actualTagKeys -join '|') -ne ($expectedTagKeys -join '|') -or @($workerTags | Where-Object Key -eq 'Drift').Count -ne 0) {
        throw 'Repair did not restore the exact five-tag object contract.'
    }

    $finalClean = Invoke-Native 'terraform' @("-chdir=$work", 'plan', '-input=false', '-detailed-exitcode', "-var-file=$v2Vars") @(0, 2)
    if ($finalClean.ExitCode -ne 0) { throw 'The repaired v2 configuration is not clean.' }
    Invoke-Native 'terraform' @("-chdir=$work", 'destroy', '-auto-approve', '-input=false', "-var-file=$v2Vars") | Out-Null
    $initialized = $false
    if ((Invoke-Aws @('s3api', 'list-buckets', '--query', "Buckets[?Name=='$bucket'].Name", '--output', 'text')).Text.Trim()) {
        throw 'S3 bucket residue detected after destroy.'
    }

    Write-Host '[e2e] v1 clean, reorder no-op, exact v2 saved plan, immutable artifact apply, refresh-only drift, repair, clean/destroy passed.'
    Write-Host 'PASS challenge-46 (difficulty 95/100, alignment A)'
}
finally {
    if ($initialized -and $runId -and (Test-Path -LiteralPath $work)) {
        try {
            Invoke-Native 'terraform' @("-chdir=$work", 'destroy', '-auto-approve', '-input=false', "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint", '-var=catalog_path=../fixtures/catalog-v2.json') @(0, 1) | Out-Null
        }
        catch {}
    }
    foreach ($name in $envBefore.Keys) {
        [Environment]::SetEnvironmentVariable($name, $envBefore[$name])
    }
    Get-Process 'terraform-provider-*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) {
        $resolved = [IO.Path]::GetFullPath($tempRoot)
        $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolved.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
            try { Remove-Item -LiteralPath $resolved -Recurse -Force }
            catch {
                Start-Sleep -Milliseconds 500
                try { Remove-Item -LiteralPath $resolved -Recurse -Force } catch {}
            }
        }
    }
}
