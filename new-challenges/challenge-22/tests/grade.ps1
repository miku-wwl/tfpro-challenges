param(
    [string]$Candidate = (Join-Path $PSScriptRoot "../starter"),
    [string]$LocalstackEndpoint = "http://localhost:4566",
    [switch]$UnitOnly
)

function Assert-LoopbackEndpoint([string]$Endpoint) {
    $uri = $null
    if ([string]::IsNullOrEmpty($Endpoint) -or $Endpoint.IndexOf([char]13) -ge 0 -or $Endpoint.IndexOf([char]10) -ge 0) {
        throw "LocalstackEndpoint must not contain CR or LF."
    }
    $match = [regex]::Match($Endpoint, '\Ahttps?://(?:localhost|127\.0\.0\.1|\[::1\]):(?<port>[1-9][0-9]{0,4})\z', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if (-not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or
        -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
        $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or $uri.PathAndQuery -ne '/' -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or $uri.Port -ne [int]$match.Groups['port'].Value) {
        throw "LocalstackEndpoint must be an HTTP(S) loopback root origin with an explicit port from 1 to 65535."
    }
}
Assert-LoopbackEndpoint $LocalstackEndpoint
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $text = @(& $File @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($code -notin $Allowed) {
        throw "$File $($Arguments -join ' ') failed with exit $code.`n$($text -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ ExitCode = $code; Text = ($text -join [Environment]::NewLine) }
}

function Invoke-Aws([string[]]$Arguments, [int[]]$Allowed = @(0)) {
    return Invoke-Native 'aws' (@('--endpoint-url', $LocalstackEndpoint) + $Arguments) $Allowed
}

function Copy-CleanTree([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in @('.terraform', '.terraform.lock.hcl', 'terraform.tfstate', 'terraform.tfstate.backup', '.terraform.tfstate.lock.info') -or
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

function Write-Utf8([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Write-BackendConfig([string]$Path, [string]$Bucket, [string]$Key, [string]$Table) {
    Write-Utf8 $Path @"
bucket = "$Bucket"
key = "$Key"
region = "us-east-1"
dynamodb_table = "$Table"
access_key = "test"
secret_key = "test"
use_path_style = true
skip_credentials_validation = true
skip_metadata_api_check = true
skip_requesting_account_id = true
endpoints = { s3 = "$LocalstackEndpoint", dynamodb = "$LocalstackEndpoint" }
"@
}

function Get-StateAddresses([string]$Root) {
    $result = Invoke-Native 'terraform' @("-chdir=$Root", 'state', 'list')
    return @(($result.Text -split "`r?`n") | Where-Object { $_ } | Sort-Object)
}

function Assert-PlanActions([string]$Root, [string]$Plan, [int]$Count, [string]$Action, [string]$Label) {
    $planJson = ((Invoke-Native 'terraform' @("-chdir=$Root", 'show', '-json', $Plan)).Text | ConvertFrom-Json)
    $changes = @($planJson.resource_changes | Where-Object { (@($_.change.actions) -join ',') -ne 'no-op' })
    $wrong = @($changes | Where-Object { (@($_.change.actions) -join ',') -cne $Action })
    if ($changes.Count -ne $Count -or $wrong.Count -ne 0) {
        $summary = @($changes | ForEach-Object { "$($_.address):$(@($_.change.actions) -join ',')" }) -join '; '
        throw "$Label expected $Count '$Action' changes, found: $summary"
    }
}

function Remove-VersionedBucket([string]$Bucket) {
    if ([string]::IsNullOrWhiteSpace($Bucket) -or $Bucket -notmatch '^tfpro-c22-state-[a-z0-9]{10}$') {
        throw "Refusing to remove unexpected backend bucket '$Bucket'."
    }
    $listed = Invoke-Aws @('s3api', 'list-object-versions', '--bucket', $Bucket, '--output', 'json') @(0, 255)
    if ($listed.ExitCode -eq 0 -and $listed.Text) {
        $document = $listed.Text | ConvertFrom-Json
        $entries = @()
        if ($document.PSObject.Properties['Versions']) { $entries += @($document.Versions) }
        if ($document.PSObject.Properties['DeleteMarkers']) { $entries += @($document.DeleteMarkers) }
        foreach ($entry in $entries) {
            if ($null -ne $entry -and $entry.Key -and $entry.VersionId) {
                Invoke-Aws @('s3api', 'delete-object', '--bucket', $Bucket, '--key', [string]$entry.Key, '--version-id', [string]$entry.VersionId) @(0, 255) | Out-Null
            }
        }
    }
    Invoke-Aws @('s3api', 'delete-bucket', '--bucket', $Bucket) @(0, 255) | Out-Null
}

function Assert-ResourceSet([string]$Text, [string[]]$Expected, [string]$Label) {
    $actual = @([regex]::Matches($Text, '(?m)^\s*resource\s+"([^"]+)"\s+"([^"]+)"\s*\{') | ForEach-Object { "$($_.Groups[1].Value).$($_.Groups[2].Value)" } | Sort-Object)
    $wanted = @($Expected | Sort-Object)
    if (($actual -join '|') -cne ($wanted -join '|')) {
        throw "$Label resource set is not exact. Expected $($wanted -join ', '); found $($actual -join ', ')."
    }
}

$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$challengeRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$fixtureRoot = Join-Path $challengeRoot 'fixtures'
$producerSource = Join-Path $candidatePath 'producer'
$consumerSource = Join-Path $candidatePath 'consumer'
if (-not (Test-Path -LiteralPath $producerSource -PathType Container) -or -not (Test-Path -LiteralPath $consumerSource -PathType Container)) {
    throw 'Candidate must contain producer and consumer root modules.'
}

$expectedFiles = @('backend.tf', 'main.tf', 'outputs.tf', 'providers.tf', 'variables.tf', 'versions.tf')
foreach ($root in @($producerSource, $consumerSource)) {
    $files = @(Get-ChildItem -LiteralPath $root -File | Select-Object -ExpandProperty Name | Sort-Object)
    if (($files -join '|') -cne (($expectedFiles | Sort-Object) -join '|')) {
        throw "$root must contain exactly the six supplied Terraform files."
    }
}

$sourceFiles = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File -Filter '*.tf')
foreach ($file in $sourceFiles) {
    $raw = [IO.File]::ReadAllText($file.FullName)
    if ($raw -match '(?i)\bTODO\b|not implemented|incomplete') {
        throw "Unfinished marker found in $($file.FullName)."
    }
}

$producerText = (@(Get-ChildItem -LiteralPath $producerSource -File -Filter '*.tf' | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n")
$consumerText = (@(Get-ChildItem -LiteralPath $consumerSource -File -Filter '*.tf' | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n")
$allTf = $producerText + "`n" + $consumerText
if (([regex]::Matches($allTf, 'required_version\s*=\s*"~> 1\.6"')).Count -ne 2 -or
    ([regex]::Matches($allTf, 'version\s*=\s*"~> 5\.100"')).Count -ne 2) {
    throw 'Both roots require the exact Terraform and AWS provider constraints.'
}

foreach ($backend in @((Join-Path $producerSource 'backend.tf'), (Join-Path $consumerSource 'backend.tf'))) {
    $text = [IO.File]::ReadAllText($backend)
    if ($text -notmatch 'backend\s+"s3"\s*\{\s*\}' -or $text -match '(?i)bucket\s*=|key\s*=|region\s*=|endpoint|access_key|secret_key|dynamodb_table') {
        throw "$backend must contain an empty partial S3 backend without committed settings."
    }
}

if ($allTf -match '(?i)ignore_changes|state\s+push|force-unlock|-lock=false|aws_dynamodb|aws_s3_bucket\s+"backend"') {
    throw 'Forbidden drift suppression, state mutation, lock bypass, or backend ownership was found.'
}
Assert-ResourceSet $producerText @('terraform_data.catalog_guard', 'aws_s3_bucket.artifacts', 'aws_s3_bucket_versioning.artifacts', 'aws_s3_object.release') 'producer'
Assert-ResourceSet $consumerText @('terraform_data.contract_guard', 'aws_s3_bucket.receipts', 'aws_s3_bucket_versioning.receipts', 'aws_s3_object.receipt') 'consumer'
if (([regex]::Matches($consumerText, 'data\s+"terraform_remote_state"\s+"producer"\s*\{')).Count -ne 1 -or
    $consumerText -notmatch 'backend\s*=\s*"s3"') {
    throw 'consumer must declare exactly one S3 terraform_remote_state producer data source.'
}
foreach ($required in @('access_key', 'secret_key', 'use_path_style', 'skip_credentials_validation', 'skip_metadata_api_check', 'skip_requesting_account_id', 'endpoints')) {
    if ($consumerText -notmatch "(?m)^\s*$required\s*=") {
        throw "consumer remote-state contract is missing $required."
    }
}
if ($allTf -match '(?m)^\s*(ec2|iam|sns|dynamodb)\s*=\s*var\.localstack_endpoint') {
    throw 'Only S3 and STS provider endpoints are allowed.'
}

$testText = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'producer.tftest.hcl'))
if ($testText -match '(?i)mock_provider|override_(resource|data|module)' -or
    ([regex]::Matches($testText, '(?m)^run\s+"')).Count -ne 9) {
    throw 'Canonical suite must contain exactly 9 Terraform 1.6-compatible runs and no mock or override blocks.'
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("tfpro-c22-grade-" + [Guid]::NewGuid().ToString('N'))
$unitProducer = Join-Path $tempRoot 'unit-producer'
$unitConsumer = Join-Path $tempRoot 'unit-consumer'
$producerWork = Join-Path $tempRoot 'producer'
$consumerWork = Join-Path $tempRoot 'consumer'
$pluginCache = Join-Path $tempRoot 'plugin-cache'
$envBefore = @{}
foreach ($name in @('AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_DEFAULT_REGION', 'AWS_EC2_METADATA_DISABLED', 'TF_PLUGIN_CACHE_DIR')) {
    $envBefore[$name] = [Environment]::GetEnvironmentVariable($name)
}

$runId = $null
$suffix = $null
$stateBucket = $null
$lockTable = $null
$artifactBucket = $null
$receiptBucket = $null
$producerInitialized = $false
$consumerInitialized = $false
$currentRelease = 'v1'

try {
    New-Item -ItemType Directory -Path $pluginCache -Force | Out-Null
    $env:TF_PLUGIN_CACHE_DIR = $pluginCache
    Copy-CleanTree $producerSource $unitProducer
    Copy-CleanTree $consumerSource $unitConsumer
    New-Item -ItemType Directory -Path (Join-Path $unitProducer 'tests') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'producer.tftest.hcl') -Destination (Join-Path $unitProducer 'tests/producer.tftest.hcl')

    Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $unitProducer) | Out-Null
    Invoke-Native 'terraform' @('fmt', '-check', '-recursive', $unitConsumer) | Out-Null
    Invoke-Native 'terraform' @("-chdir=$unitProducer", 'init', '-backend=false', '-input=false') | Out-Null
    Invoke-Native 'terraform' @("-chdir=$unitConsumer", 'init', '-backend=false', '-input=false') | Out-Null
    Invoke-Native 'terraform' @("-chdir=$unitProducer", 'validate', '-no-color') | Out-Null
    Invoke-Native 'terraform' @("-chdir=$unitConsumer", 'validate', '-no-color') | Out-Null
    $test = Invoke-Native 'terraform' @("-chdir=$unitProducer", 'test', '-test-directory=tests', '-no-color')
    if ($test.Text -notmatch 'Success! 9 passed, 0 failed') {
        throw "Canonical run count/result mismatch.`n$($test.Text)"
    }
    Write-Host '[unit] both roots passed fmt/init/validate; 9 Terraform 1.6 canonical runs passed.'
    if ($UnitOnly) {
        Write-Host 'PASS challenge-22 UnitOnly'
        return
    }

    $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get
    foreach ($service in @('s3', 'dynamodb', 'sts')) {
        if ($null -eq $health.services.$service -or [string]$health.services.$service -notmatch 'available|running') {
            throw "LocalStack service $service is not available."
        }
    }

    $env:AWS_ACCESS_KEY_ID = 'test'
    $env:AWS_SECRET_ACCESS_KEY = 'test'
    $env:AWS_DEFAULT_REGION = 'us-east-1'
    $env:AWS_EC2_METADATA_DISABLED = 'true'

    $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 10)
    $runId = "c22-$suffix"
    $stateBucket = "tfpro-c22-state-$suffix"
    $lockTable = "tfpro-c22-lock-$suffix"
    $artifactBucket = "tfpro-c22-artifacts-$runId"
    $receiptBucket = "tfpro-c22-receipts-$runId"
    $producerStateKey = 'producer/terraform.tfstate'
    $consumerStateKey = 'consumer/terraform.tfstate'

    Invoke-Aws @('s3api', 'create-bucket', '--bucket', $stateBucket, '--region', 'us-east-1') | Out-Null
    Invoke-Aws @('s3api', 'put-bucket-versioning', '--bucket', $stateBucket, '--versioning-configuration', 'Status=Enabled') | Out-Null
    Invoke-Aws @('dynamodb', 'create-table', '--table-name', $lockTable, '--attribute-definitions', 'AttributeName=LockID,AttributeType=S', '--key-schema', 'AttributeName=LockID,KeyType=HASH', '--billing-mode', 'PAY_PER_REQUEST', '--region', 'us-east-1') | Out-Null
    Invoke-Aws @('dynamodb', 'wait', 'table-exists', '--table-name', $lockTable, '--region', 'us-east-1') | Out-Null

    Copy-CleanTree $producerSource $producerWork
    Copy-CleanTree $consumerSource $consumerWork
    $producerBackendPending = Join-Path $producerWork 'backend.tf.pending'
    Move-Item -LiteralPath (Join-Path $producerWork 'backend.tf') -Destination $producerBackendPending
    Invoke-Native 'terraform' @("-chdir=$producerWork", 'init', '-input=false') | Out-Null
    $producerInitialized = $true

    $v1 = Join-Path $fixtureRoot 'release-v1.tfvars.json'
    $v2 = Join-Path $fixtureRoot 'release-v2.tfvars.json'
    $producerBase = @('-input=false', "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
    $producerV1Plan = Join-Path $tempRoot 'producer-v1.tfplan'
    Invoke-Native 'terraform' (@("-chdir=$producerWork", 'plan', "-out=$producerV1Plan") + $producerBase + @("-var-file=$v1")) | Out-Null
    Assert-PlanActions $producerWork $producerV1Plan 5 'create' 'producer v1 saved plan'
    Invoke-Native 'terraform' @("-chdir=$producerWork", 'apply', '-input=false', '-auto-approve', $producerV1Plan) | Out-Null

    $beforeMigration = Get-StateAddresses $producerWork
    if ($beforeMigration.Count -ne 5) {
        throw "Producer local state expected 5 instances, found $($beforeMigration.Count)."
    }
    Move-Item -LiteralPath $producerBackendPending -Destination (Join-Path $producerWork 'backend.tf')
    $producerBackendConfig = Join-Path $tempRoot 'producer.backend.hcl'
    Write-BackendConfig $producerBackendConfig $stateBucket $producerStateKey $lockTable
    Invoke-Native 'terraform' @("-chdir=$producerWork", 'init', '-migrate-state', '-force-copy', '-input=false', "-backend-config=$producerBackendConfig") | Out-Null

    $afterMigration = Get-StateAddresses $producerWork
    if (($beforeMigration -join '|') -cne ($afterMigration -join '|')) {
        throw 'Local to S3 migration changed the producer resource address set.'
    }
    Invoke-Aws @('s3api', 'head-object', '--bucket', $stateBucket, '--key', $producerStateKey) | Out-Null
    $producerClean = Invoke-Native 'terraform' (@("-chdir=$producerWork", 'plan', '-detailed-exitcode') + $producerBase + @("-var-file=$v1")) @(0, 2)
    if ($producerClean.ExitCode -ne 0) {
        throw 'Producer migration did not preserve a clean v1 plan.'
    }

    $consumerBackendConfig = Join-Path $tempRoot 'consumer.backend.hcl'
    Write-BackendConfig $consumerBackendConfig $stateBucket $consumerStateKey $lockTable
    Invoke-Native 'terraform' @("-chdir=$consumerWork", 'init', '-input=false', "-backend-config=$consumerBackendConfig") | Out-Null
    $consumerInitialized = $true
    $consumerBase = @('-input=false', "-var=run_id=$runId", "-var=state_bucket=$stateBucket", "-var=localstack_endpoint=$LocalstackEndpoint")
    $consumerV1Plan = Join-Path $tempRoot 'consumer-v1.tfplan'
    Invoke-Native 'terraform' (@("-chdir=$consumerWork", 'plan', "-out=$consumerV1Plan") + $consumerBase + @('-var=expected_release_version=v1')) | Out-Null
    Assert-PlanActions $consumerWork $consumerV1Plan 5 'create' 'consumer v1 saved plan'
    Invoke-Native 'terraform' @("-chdir=$consumerWork", 'apply', '-input=false', '-auto-approve', $consumerV1Plan) | Out-Null
    Invoke-Aws @('s3api', 'head-object', '--bucket', $stateBucket, '--key', $consumerStateKey) | Out-Null

    foreach ($name in @('api', 'worker')) {
        $receiptPath = Join-Path $tempRoot "$name-receipt.json"
        Invoke-Aws @('s3api', 'get-object', '--bucket', $receiptBucket, '--key', "receipts/$name.json", $receiptPath) | Out-Null
        $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
        if ($receipt.contract_version -ne 1 -or $receipt.release_version -ne 'v1' -or
            $receipt.source_bucket -cne $artifactBucket -or $receipt.source_key -cne "releases/$name.txt" -or
            [string]$receipt.source_sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Receipt $name does not match the v1 producer contract."
        }
    }

    $premature = Invoke-Native 'terraform' (@("-chdir=$consumerWork", 'plan', '-no-color') + $consumerBase + @('-var=expected_release_version=v2')) @(1)
    if ($premature.Text -notmatch 'Producer release is not the expected version') {
        throw 'Consumer did not reject v2 before the producer published v2.'
    }

    $producerV2Plan = Join-Path $tempRoot 'producer-v2.tfplan'
    Invoke-Native 'terraform' (@("-chdir=$producerWork", 'plan', "-out=$producerV2Plan") + $producerBase + @("-var-file=$v2")) | Out-Null
    Assert-PlanActions $producerWork $producerV2Plan 3 'update' 'producer v2 saved plan'
    Invoke-Native 'terraform' @("-chdir=$producerWork", 'apply', '-input=false', '-auto-approve', $producerV2Plan) | Out-Null
    $currentRelease = 'v2'

    $oldConsumer = Invoke-Native 'terraform' (@("-chdir=$consumerWork", 'plan', '-no-color') + $consumerBase + @('-var=expected_release_version=v1')) @(1)
    if ($oldConsumer.Text -notmatch 'Producer release is not the expected version') {
        throw 'Consumer did not reject its stale v1 expectation after producer v2.'
    }
    $consumerV2Plan = Join-Path $tempRoot 'consumer-v2.tfplan'
    Invoke-Native 'terraform' (@("-chdir=$consumerWork", 'plan', "-out=$consumerV2Plan") + $consumerBase + @('-var=expected_release_version=v2')) | Out-Null
    Assert-PlanActions $consumerWork $consumerV2Plan 3 'update' 'consumer v2 saved plan'
    Invoke-Native 'terraform' @("-chdir=$consumerWork", 'apply', '-input=false', '-auto-approve', $consumerV2Plan) | Out-Null

    foreach ($name in @('api', 'worker')) {
        $tags = ((Invoke-Aws @('s3api', 'get-object-tagging', '--bucket', $artifactBucket, '--key', "releases/$name.txt", '--output', 'json')).Text | ConvertFrom-Json).TagSet
        $tagMap = @{}
        foreach ($tag in $tags) { $tagMap[$tag.Key] = $tag.Value }
        if ($tagMap.Release -cne 'v2' -or $tagMap.RunId -cne $runId -or [string]$tagMap.Sha256 -notmatch '^[0-9a-f]{64}$') {
            throw "Producer object $name has an invalid v2 tag contract."
        }
    }

    $producerFinal = Invoke-Native 'terraform' (@("-chdir=$producerWork", 'plan', '-detailed-exitcode') + $producerBase + @("-var-file=$v2")) @(0, 2)
    $consumerFinal = Invoke-Native 'terraform' (@("-chdir=$consumerWork", 'plan', '-detailed-exitcode') + $consumerBase + @('-var=expected_release_version=v2')) @(0, 2)
    if ($producerFinal.ExitCode -ne 0 -or $consumerFinal.ExitCode -ne 0) {
        throw 'The final producer or consumer plan is not clean.'
    }

    Invoke-Native 'terraform' (@("-chdir=$consumerWork", 'destroy', '-auto-approve') + $consumerBase + @('-var=expected_release_version=v2')) | Out-Null
    $consumerInitialized = $false
    $receiptRemaining = (Invoke-Aws @('s3api', 'list-buckets', '--query', "Buckets[?Name=='$receiptBucket'].Name", '--output', 'text')).Text.Trim()
    $artifactStillPresent = (Invoke-Aws @('s3api', 'list-buckets', '--query', "Buckets[?Name=='$artifactBucket'].Name", '--output', 'text')).Text.Trim()
    if ($receiptRemaining -or -not $artifactStillPresent) {
        throw 'Consumer-first destroy did not preserve the producer while removing receipts.'
    }

    Invoke-Native 'terraform' (@("-chdir=$producerWork", 'destroy', '-auto-approve') + $producerBase + @("-var-file=$v2")) | Out-Null
    $producerInitialized = $false
    $artifactRemaining = (Invoke-Aws @('s3api', 'list-buckets', '--query', "Buckets[?Name=='$artifactBucket'].Name", '--output', 'text')).Text.Trim()
    if ($artifactRemaining) {
        throw 'Producer artifact bucket remained after ordered destroy.'
    }

    Invoke-Aws @('dynamodb', 'delete-table', '--table-name', $lockTable, '--region', 'us-east-1') | Out-Null
    Invoke-Aws @('dynamodb', 'wait', 'table-not-exists', '--table-name', $lockTable, '--region', 'us-east-1') | Out-Null
    $lockTable = $null
    Remove-VersionedBucket $stateBucket
    $stateBucket = $null

    Write-Host '[e2e] local saved plan -> S3 migration -> remote contract -> v2 saved plans -> ordered destroy passed.'
    Write-Host 'PASS challenge-22 (alignment A, difficulty 96/100)'
}
finally {
    if ($consumerInitialized -and $runId -and (Test-Path -LiteralPath $consumerWork)) {
        try {
            Invoke-Native 'terraform' @("-chdir=$consumerWork", 'destroy', '-auto-approve', '-input=false', "-var=run_id=$runId", "-var=state_bucket=$stateBucket", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=expected_release_version=$currentRelease") @(0, 1) | Out-Null
        }
        catch {}
    }
    if ($producerInitialized -and $runId -and (Test-Path -LiteralPath $producerWork)) {
        try {
            $fixture = if ($currentRelease -eq 'v2') { 'release-v2.tfvars.json' } else { 'release-v1.tfvars.json' }
            Invoke-Native 'terraform' @("-chdir=$producerWork", 'destroy', '-auto-approve', '-input=false', "-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint", "-var-file=$(Join-Path $fixtureRoot $fixture)") @(0, 1) | Out-Null
        }
        catch {}
    }
    if ($lockTable) {
        try { Invoke-Aws @('dynamodb', 'delete-table', '--table-name', $lockTable, '--region', 'us-east-1') @(0, 255) | Out-Null } catch {}
    }
    if ($stateBucket) {
        try { Remove-VersionedBucket $stateBucket } catch {}
    }
    foreach ($name in $envBefore.Keys) {
        [Environment]::SetEnvironmentVariable($name, $envBefore[$name])
    }
    Get-Process 'terraform-provider-*' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) } | Stop-Process -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTemp.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
            try { Remove-Item -LiteralPath $resolvedTemp -Recurse -Force } catch {}
        }
    }
}
