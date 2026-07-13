param(
    [string]$Candidate = (Join-Path $PSScriptRoot "../starter"),
    [string]$LocalstackEndpoint = "http://localhost:4566"
)

$ErrorActionPreference = "Stop"

function Assert-LoopbackEndpoint([string]$Endpoint) {
    $uri = $null
    # Validate the raw origin before URI normalization so encoded traversal,
    # backslashes, userinfo, paths, query strings, and fragments cannot hide.
    if ($Endpoint -notmatch '(?i)^https?://(?:localhost|127\.0\.0\.1|\[::1\]):[1-9][0-9]{0,4}$' -or
        -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @("http", "https") -or
        $uri.Host -notin @("localhost", "127.0.0.1", "::1") -or
        $uri.Port -lt 1 -or
        $uri.PathAndQuery -ne "/") {
        throw "LocalstackEndpoint must be an HTTP(S) loopback origin with an explicit port."
    }
}

function Copy-CleanTree([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in @(".terraform", ".terraform.lock.hcl", "terraform.tfstate", "terraform.tfstate.backup", ".terraform.tfstate.lock.info") -or
            $item.Name -like "tests-generated*" -or $item.Extension -eq ".tfplan") {
            continue
        }
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) { Copy-CleanTree $item.FullName $target } else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
    }
}

function Remove-HclComments([string]$Text) {
    $builder = [Text.StringBuilder]::new($Text.Length)
    $state = "code"
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $current = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
        if ($state -eq "code") {
            if ($current -eq '"') { [void]$builder.Append($current); $state = "string" }
            elseif ($current -eq '#') { [void]$builder.Append(' '); $state = "line" }
            elseif ($current -eq '/' -and $next -eq '/') { [void]$builder.Append("  "); $i++; $state = "line" }
            elseif ($current -eq '/' -and $next -eq '*') { [void]$builder.Append("  "); $i++; $state = "block" }
            else { [void]$builder.Append($current) }
        }
        elseif ($state -eq "string") {
            [void]$builder.Append($current)
            if ($current -eq '\' -and $i + 1 -lt $Text.Length) { $i++; [void]$builder.Append($Text[$i]) }
            elseif ($current -eq '"') { $state = "code" }
        }
        elseif ($state -eq "line") {
            if ($current -eq "`n") { [void]$builder.Append($current); $state = "code" }
            else { [void]$builder.Append(' ') }
        }
        else {
            if ($current -eq '*' -and $next -eq '/') { [void]$builder.Append("  "); $i++; $state = "code" }
            elseif ($current -eq "`n") { [void]$builder.Append($current) }
            else { [void]$builder.Append(' ') }
        }
    }
    return $builder.ToString()
}

function Get-HclBlocks([string]$Text, [string]$HeaderPattern) {
    $blocks = [Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Text, $HeaderPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        $open = $Text.IndexOf('{', $match.Index)
        if ($open -lt 0) { continue }
        $depth = 0
        $inString = $false
        for ($i = $open; $i -lt $Text.Length; $i++) {
            $current = $Text[$i]
            if ($inString) {
                if ($current -eq '\') { $i++; continue }
                if ($current -eq '"') { $inString = $false }
                continue
            }
            if ($current -eq '"') { $inString = $true; continue }
            if ($current -eq '{') { $depth++ }
            elseif ($current -eq '}') {
                $depth--
                if ($depth -eq 0) {
                    $blocks.Add($Text.Substring($match.Index, $i - $match.Index + 1))
                    break
                }
            }
        }
    }
    return @($blocks)
}

function Get-OneHclBlock([string]$Text, [string]$HeaderPattern, [string]$Context) {
    $blocks = @(Get-HclBlocks $Text $HeaderPattern)
    if ($blocks.Count -ne 1) { throw "$Context must appear exactly once." }
    return $blocks[0]
}

function Assert-ExactAssignment([string]$Block, [string]$Name, [string]$ExpectedPattern, [string]$Context) {
    $assignments = @([regex]::Matches($Block, '(?m)^[ \t]*' + [regex]::Escape($Name) + '\s*=\s*(?<value>[^\r\n]+?)\s*$'))
    if ($assignments.Count -ne 1 -or $assignments[0].Groups['value'].Value.Trim() -notmatch ('^(?:' + $ExpectedPattern + ')$')) {
        throw "$Context must set $Name exactly once to the required safe value."
    }
}

function Assert-AwsProviderPair([string]$Source, [string[]]$Services, [string]$Context) {
    $blocks = @(Get-HclBlocks $Source '(?m)^[ \t]*provider\s+"aws"\s*\{')
    if ($blocks.Count -ne 2) { throw "$Context must contain exactly two AWS provider blocks." }
    $defaults = @($blocks | Where-Object { $_ -notmatch '(?m)^[ \t]*alias\s*=' })
    $dr = @($blocks | Where-Object { [regex]::Matches($_, '(?m)^[ \t]*alias\s*=\s*"dr"\s*$').Count -eq 1 })
    if ($defaults.Count -ne 1 -or $dr.Count -ne 1) { throw "$Context needs one default and one aws.dr provider." }
    $pairs = @(
        @{ Block = $defaults[0]; Region = 'var\.primary_region'; Name = "$Context default provider" },
        @{ Block = $dr[0]; Region = 'var\.dr_region'; Name = "$Context dr provider" }
    )
    foreach ($pair in $pairs) {
        Assert-ExactAssignment $pair.Block 'region' $pair.Region $pair.Name
        Assert-ExactAssignment $pair.Block 'access_key' '"test"' $pair.Name
        Assert-ExactAssignment $pair.Block 'secret_key' '"test"' $pair.Name
        foreach ($flag in @('skip_credentials_validation', 'skip_metadata_api_check', 'skip_requesting_account_id')) {
            Assert-ExactAssignment $pair.Block $flag 'true' $pair.Name
        }
        foreach ($forbidden in @('profile', 'token', 'shared_config_files', 'shared_credentials_files', 'web_identity_token_file')) {
            if ([regex]::Matches($pair.Block, '(?m)^[ \t]*' + [regex]::Escape($forbidden) + '\s*=').Count) {
                throw "$($pair.Name) must not use $forbidden."
            }
        }
        if ($pair.Block -match '(?m)^[ \t]*(?:assume_role|assume_role_with_web_identity)\s*\{') {
            throw "$($pair.Name) must not use role or web-identity credential blocks."
        }
        $endpointBlocks = @(Get-HclBlocks $pair.Block '(?m)^[ \t]*endpoints\s*\{')
        if ($endpointBlocks.Count -ne 1) { throw "$($pair.Name) must contain exactly one endpoints block." }
        $endpointBlock = $endpointBlocks[0]
        foreach ($service in $Services) {
            Assert-ExactAssignment $endpointBlock $service 'var\.localstack_endpoint' $pair.Name
        }
        $actualKeys = @([regex]::Matches($endpointBlock, '(?m)^[ \t]*(?<key>[a-z0-9_]+)\s*=') | ForEach-Object { $_.Groups['key'].Value })
        if ($actualKeys.Count -ne $Services.Count -or (Compare-Object ($actualKeys | Sort-Object) ($Services | Sort-Object))) {
            throw "$($pair.Name) endpoints keys must exactly match: $($Services -join ', ')."
        }
    }
}

function Assert-SafePlan([string]$Root, [string]$PlanPath, [string]$Context, [bool]$RequireChanges) {
    $raw = (& terraform "-chdir=$Root" show -json $PlanPath 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Could not render $Context plan JSON: $raw" }
    $plan = $raw | ConvertFrom-Json -Depth 100
    $changes = @($plan.resource_changes | Where-Object { $_.change.actions -notcontains "no-op" -and $_.mode -eq "managed" })
    $destructive = @($changes | Where-Object { $_.change.actions -contains "delete" })
    if ($destructive.Count) {
        throw "$Context plan contains delete/replace actions: $($destructive.address -join ', ')"
    }
    if ($RequireChanges -and $changes.Count -eq 0) { throw "$Context plan unexpectedly contains no managed changes." }
    return $changes
}

function Invoke-AwsJson([string[]]$Arguments) {
    $raw = (& aws @Arguments --output json 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "AWS CLI failed: aws $($Arguments -join ' ')`n$raw" }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json -Depth 100
}

# This guard runs before health checks, AWS CLI, or Terraform network activity.
Assert-LoopbackEndpoint $LocalstackEndpoint

$LabRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$CandidateRoot = (Resolve-Path $Candidate).Path
$foundationRoot = Join-Path $CandidateRoot "foundation"
$fleetRoot = Join-Path $CandidateRoot "fleet"
foreach ($root in @($foundationRoot, $fleetRoot)) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Candidate is missing root: $root" }
}

$foundationSource = Remove-HclComments (((Get-ChildItem $foundationRoot -Recurse -Filter *.tf -File) | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n")
$fleetSource = Remove-HclComments (((Get-ChildItem $fleetRoot -File -Filter *.tf) | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n")
$childRoot = Join-Path $fleetRoot "modules/regional"
$childSource = Remove-HclComments (((Get-ChildItem $childRoot -File -Filter *.tf) | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n")

foreach ($entry in @(
    @{ Source = $foundationSource; Name = "foundation" },
    @{ Source = $fleetSource; Name = "fleet" }
)) {
    $endpointVariable = Get-OneHclBlock $entry.Source '(?m)^[ \t]*variable\s+"localstack_endpoint"\s*\{' "$($entry.Name) localstack_endpoint variable"
    Assert-ExactAssignment $endpointVariable 'default' '"http://localhost:4566"' "$($entry.Name) localstack_endpoint"
}
Assert-AwsProviderPair $foundationSource @('ec2', 'iam', 'sts') 'foundation root'
Assert-AwsProviderPair $fleetSource @('ec2', 'sts') 'fleet root'
if ((Get-HclBlocks $childSource '(?m)^[ \t]*provider\s+"aws"\s*\{').Count -ne 0) {
    throw "The regional child module must receive providers from its caller."
}
if ([regex]::Matches("$foundationSource`n$fleetSource`n$childSource", 'required_version\s*=\s*"~>\s*1\.6"').Count -ne 3 -or
    [regex]::Matches("$foundationSource`n$fleetSource`n$childSource", 'version\s*=\s*"~>\s*5\.100"').Count -ne 3) {
    throw "Every root/module must pin Terraform ~> 1.6 and AWS provider ~> 5.100."
}
if ("$foundationSource`n$fleetSource`n$childSource" -match '(?i)autoscaling') {
    throw "Challenge 35 must use the LocalStack Community EC2 control-plane model, not Auto Scaling APIs."
}

$foundationMain = Remove-HclComments (Get-Content -Raw (Join-Path $foundationRoot "main.tf"))
$fleetMain = Remove-HclComments (Get-Content -Raw (Join-Path $fleetRoot "main.tf"))
$childMain = Remove-HclComments (Get-Content -Raw (Join-Path $childRoot "main.tf"))
foreach ($kind in @('aws_vpc', 'aws_subnet', 'aws_security_group')) {
    $block = Get-OneHclBlock $foundationMain ('(?m)^[ \t]*resource\s+"' + $kind + '"\s+"dr"\s*\{') "foundation $kind.dr"
    Assert-ExactAssignment $block 'provider' 'aws\.dr' "foundation $kind.dr"
}
$amiDr = Get-OneHclBlock $fleetMain '(?m)^[ \t]*data\s+"aws_ami"\s+"dr"\s*\{' 'fleet aws_ami.dr'
Assert-ExactAssignment $amiDr 'provider' 'aws\.dr' 'fleet aws_ami.dr'
$primaryModule = Get-OneHclBlock $fleetMain '(?m)^[ \t]*module\s+"primary"\s*\{' 'fleet module.primary'
$drModule = Get-OneHclBlock $fleetMain '(?m)^[ \t]*module\s+"dr"\s*\{' 'fleet module.dr'
Assert-ExactAssignment $primaryModule 'providers' '\{\s*aws\s*=\s*aws\s*\}' 'fleet module.primary'
Assert-ExactAssignment $drModule 'providers' '\{\s*aws\s*=\s*aws\.dr\s*\}' 'fleet module.dr'
if ($fleetMain -notmatch 'data\s+"terraform_remote_state"\s+"foundation"' -or
    $fleetMain -notmatch '"\$\{row\.name\}@\$\{row\.location\}"' -or
    $childMain -notmatch '"\$\{fleet_key\}#\$\{format\("%02d",\s*index\s*\+\s*1\)\}"') {
    throw "Fleet needs remote state plus stable name@location and name@location#NN identities."
}
$launchTemplate = Get-OneHclBlock $childMain '(?m)^[ \t]*resource\s+"aws_launch_template"\s+"fleet"\s*\{' 'regional aws_launch_template.fleet'
$revision = Get-OneHclBlock $childMain '(?m)^[ \t]*resource\s+"terraform_data"\s+"launch_template_revision"\s*\{' 'regional terraform_data.launch_template_revision'
$replica = Get-OneHclBlock $childMain '(?m)^[ \t]*resource\s+"aws_instance"\s+"replica"\s*\{' 'regional aws_instance.replica'
$profile = Get-OneHclBlock $launchTemplate '(?m)^[ \t]*iam_instance_profile\s*\{' 'launch template iam_instance_profile'
$templateLifecycle = Get-OneHclBlock $launchTemplate '(?m)^[ \t]*lifecycle\s*\{' 'launch template lifecycle'
$instanceLaunch = Get-OneHclBlock $replica '(?m)^[ \t]*launch_template\s*\{' 'replica launch_template'
$instanceLifecycle = Get-OneHclBlock $replica '(?m)^[ \t]*lifecycle\s*\{' 'replica lifecycle'
Assert-ExactAssignment $launchTemplate 'image_id' 'var\.ami_id' 'regional launch template'
Assert-ExactAssignment $launchTemplate 'instance_type' 'each\.value\.instance_type' 'regional launch template'
Assert-ExactAssignment $launchTemplate 'vpc_security_group_ids' '\[var\.security_group_id\]' 'regional launch template'
Assert-ExactAssignment $profile 'name' 'var\.instance_profile_name' 'launch template IAM profile'
Assert-ExactAssignment $templateLifecycle 'ignore_changes' '\[tag_specifications\]' 'launch template lifecycle'
Assert-ExactAssignment $replica 'subnet_id' 'var\.subnet_id' 'regional EC2 replica'
Assert-ExactAssignment $instanceLaunch 'id' 'aws_launch_template\.fleet\[each\.value\.fleet_key\]\.id' 'replica launch template'
Assert-ExactAssignment $instanceLaunch 'version' '"\$Latest"' 'replica launch template'
Assert-ExactAssignment $revision 'for_each' 'local\.replicas' 'launch template revision sentinel'
Assert-ExactAssignment $revision 'id' 'aws_launch_template\.fleet\[each\.value\.fleet_key\]\.id' 'launch template revision sentinel'
Assert-ExactAssignment $revision 'version' 'aws_launch_template\.fleet\[each\.value\.fleet_key\]\.latest_version' 'launch template revision sentinel'
Assert-ExactAssignment $instanceLifecycle 'ignore_changes' '\[launch_template\]' 'replica lifecycle'
Assert-ExactAssignment $instanceLifecycle 'replace_triggered_by' '\[terraform_data\.launch_template_revision\[each\.key\]\]' 'replica lifecycle'
if ($replica -match '(?m)^[ \t]*(?:ami|instance_type|vpc_security_group_ids|iam_instance_profile)\s*=') {
    throw "EC2 replicas must inherit AMI, type, security groups, and profile from the launch template."
}
if ($launchTemplate.Count -ne 1 -or $replica.Count -ne 1) {
    throw "The regional module must manage launch templates and stable EC2 replicas."
}

$health = Invoke-RestMethod -Uri "$LocalstackEndpoint/_localstack/health" -TimeoutSec 5
foreach ($service in @("ec2", "iam", "sts")) {
    if ($health.services.$service -notin @("available", "running")) { throw "LocalStack $service is unavailable." }
}

$tempBase = [IO.Path]::GetTempPath()
$temp = Join-Path $tempBase ("tfpro-c35-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $temp "candidate"
$foundation = Join-Path $workRoot "foundation"
$fleet = Join-Path $workRoot "fleet"
$runId = "c35" + [guid]::NewGuid().ToString("N").Substring(0, 10)
$failure = $null
$created = $false
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    Copy-CleanTree $CandidateRoot $workRoot
    Copy-CleanTree (Join-Path $LabRoot "fixtures") (Join-Path $temp "fixtures")
    $created = $true

    $testCases = @(
        @{ Root = $foundation; Test = "foundation.tftest.hcl"; Passed = 3 },
        @{ Root = $fleet; Test = "fleet.tftest.hcl"; Passed = 9 }
    )
    foreach ($case in $testCases) {
        $testName = "tests-generated-$PID"
        $testDir = Join-Path $case.Root $testName
        New-Item -ItemType Directory -Force $testDir | Out-Null
        Copy-Item (Join-Path $PSScriptRoot $case.Test) $testDir -Force
        try {
            & terraform "-chdir=$($case.Root)" fmt -check -recursive
            if ($LASTEXITCODE) { throw "fmt failed for $($case.Root)" }
            & terraform "-chdir=$($case.Root)" init -backend=false -input=false -no-color
            if ($LASTEXITCODE) { throw "init failed for $($case.Root)" }
            & terraform "-chdir=$($case.Root)" validate -no-color
            if ($LASTEXITCODE) { throw "validate failed for $($case.Root)" }
            $testOutput = (& terraform "-chdir=$($case.Root)" test "-test-directory=$testName" -no-color 2>&1) -join "`n"
            Write-Host $testOutput
            $summaryCount = [regex]::Matches($testOutput, "(?m)^Success!\s+$($case.Passed) passed,\s+0 failed\.\s*$").Count
            $runPassCount = [regex]::Matches($testOutput, '(?m)^[ \t]+run\s+"[^"]+"\.\.\.\s+pass\s*$').Count
            if ($LASTEXITCODE -or $summaryCount -ne 1 -or $runPassCount -ne $case.Passed) {
                throw "Contract tests failed or were not discovered for $($case.Root)"
            }
        } finally {
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $commonVars = @("-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
    $foundationPlan = "foundation-delivery.tfplan"
    $planOutput = (& terraform "-chdir=$foundation" plan -input=false -no-color "-out=$foundationPlan" @commonVars 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Foundation saved plan failed: $planOutput" }
    $null = Assert-SafePlan $foundation $foundationPlan "foundation delivery" $true
    $applyOutput = (& terraform "-chdir=$foundation" apply -input=false -no-color -auto-approve $foundationPlan 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Foundation saved-plan apply failed: $applyOutput" }

    $fleetPlan = "fleet-delivery.tfplan"
    $planOutput = (& terraform "-chdir=$fleet" plan -input=false -no-color "-out=$fleetPlan" @commonVars 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Fleet saved plan failed: $planOutput" }
    $fleetChanges = @(Assert-SafePlan $fleet $fleetPlan "fleet delivery" $true)
    $instanceCreates = @($fleetChanges | Where-Object { $_.address -match '^module\.(?:primary|dr)\.aws_instance\.replica\[' })
    if ($instanceCreates.Count -ne 4) { throw "Fleet delivery must plan exactly four EC2 replicas, including worker #02." }
    foreach ($change in $instanceCreates) {
        $source = @($change.change.after.launch_template)
        if ($source.Count -ne 1 -or $source[0].version -ne '$Latest') {
            throw "Saved plan JSON does not preserve the replica launch-template source."
        }
    }
    $applyOutput = (& terraform "-chdir=$fleet" apply -input=false -no-color -auto-approve $fleetPlan 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Fleet saved-plan apply failed: $applyOutput" }

    $env:AWS_ACCESS_KEY_ID = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION = "us-east-1"
    $replicaRaw = (& terraform "-chdir=$fleet" output -json replica_ids 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Could not read fleet replica IDs: $replicaRaw" }
    $replicaIds = $replicaRaw | ConvertFrom-Json -AsHashtable
    $expectedReplicaKeys = @("api@dr#01", "api@primary#01", "worker@primary#01", "worker@primary#02")
    if ($replicaIds.Count -ne $expectedReplicaKeys.Count -or @($expectedReplicaKeys | Where-Object { -not $replicaIds.ContainsKey($_) }).Count) {
        throw "Real fleet did not create all four stable replicas, including worker@primary#02."
    }
    $contractsRaw = (& terraform "-chdir=$fleet" output -json fleet_contracts 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Could not read fleet contracts: $contractsRaw" }
    $contracts = $contractsRaw | ConvertFrom-Json -AsHashtable
    $amisRaw = (& terraform "-chdir=$fleet" output -json ami_ids 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Could not read selected AMIs: $amisRaw" }
    $amis = $amisRaw | ConvertFrom-Json -AsHashtable
    foreach ($replicaKey in $expectedReplicaKeys) {
        $fleetKey = $replicaKey -replace '#[0-9]+$', ''
        $role = if ($fleetKey.EndsWith('@dr')) { 'dr' } else { 'primary' }
        $region = if ($role -eq 'dr') { 'us-west-2' } else { 'us-east-1' }
        $ami = if ($role -eq 'dr') { $amis.dr } else { $amis.primary }
        $contract = $contracts[$fleetKey]
        $instanceResult = Invoke-AwsJson @("--endpoint-url", $LocalstackEndpoint, "--region", $region, "ec2", "describe-instances", "--instance-ids", $replicaIds[$replicaKey])
        $instances = @($instanceResult.Reservations | ForEach-Object { $_.Instances })
        if ($instances.Count -ne 1) { throw "Replica $replicaKey was not visible in $region." }
        $instance = $instances[0]
        $templateResult = Invoke-AwsJson @("--endpoint-url", $LocalstackEndpoint, "--region", $region, "ec2", "describe-launch-template-versions", "--launch-template-id", $contract.launch_template_id, "--versions", '$Latest')
        $template = $templateResult.LaunchTemplateVersions[0].LaunchTemplateData
        $instanceTags = @{}
        foreach ($tag in @($instance.Tags)) { $instanceTags[$tag.Key] = $tag.Value }
        $replicaNumber = [int]([regex]::Match($replicaKey, '#([0-9]+)$').Groups[1].Value)
        if ($template.ImageId -ne $ami -or
            $template.InstanceType -ne "t3.micro" -or
            $template.SecurityGroupIds -notcontains $contract.security_group_id -or
            $template.IamInstanceProfile.Name -ne "$runId-compute-profile" -or
            $instance.ImageId -ne $ami -or
            $instance.SubnetId -ne $contract.subnet_id -or
            @($contract.instance_ids) -notcontains $replicaIds[$replicaKey] -or
            $instanceTags.Fleet -ne $fleetKey -or
            $instanceTags.Owner -ne $contract.owner -or
            $instanceTags.Role -ne $role -or
            $instanceTags.Replica -ne [string]$replicaNumber -or
            $instanceTags.RunId -ne $runId -or
            $instanceTags.ManagedBy -ne 'terraform' -or
            $instanceTags.Lab -ne 'challenge-35') {
            throw "The real $replicaKey launch template, instance placement, identity, or tags are wrong."
        }
    }

    $reorderOutput = (& terraform "-chdir=$fleet" plan -detailed-exitcode -input=false -no-color @commonVars "-var=fleet_csv_path=../../fixtures/fleet-reordered.csv" 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Reordering the CSV changed managed resource identity: $reorderOutput" }

    $null = Invoke-AwsJson @("--endpoint-url", $LocalstackEndpoint, "--region", "us-east-1", "ec2", "create-tags", "--resources", $replicaIds["api@primary#01"], "--tags", "Key=Name,Value=$runId-intentional-drift")
    $recoveryPlan = "fleet-recovery.tfplan"
    $recoveryOutput = (& terraform "-chdir=$fleet" plan -input=false -no-color "-out=$recoveryPlan" @commonVars 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Drift recovery plan failed: $recoveryOutput" }
    $recoveryChanges = @(Assert-SafePlan $fleet $recoveryPlan "fleet drift recovery" $true)
    $expectedDriftAddress = 'module.primary.aws_instance.replica["api@primary#01"]'
    # Join avoids PowerShell unwrapping a one-element array and then treating
    # string indexing as character indexing ("update"[0] == "u").
    $driftActionsText = if ($recoveryChanges.Count -eq 1) { @($recoveryChanges[0].change.actions) -join ',' } else { '' }
    if ($recoveryChanges.Count -ne 1 -or
        $recoveryChanges[0].address -ne $expectedDriftAddress -or
        $driftActionsText -ne 'update') {
        $observedDrift = (@($recoveryChanges | ForEach-Object { "$($_.address):$($_.change.actions -join '+')" }) -join ', ')
        throw "Drift recovery must contain exactly one in-place update for $expectedDriftAddress and no additional managed changes. Observed: $observedDrift"
    }
    $applyOutput = (& terraform "-chdir=$fleet" apply -input=false -no-color -auto-approve $recoveryPlan 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Saved drift-recovery apply failed: $applyOutput" }

    foreach ($root in @($foundation, $fleet)) {
        $repeatOutput = (& terraform "-chdir=$root" plan -detailed-exitcode -input=false -no-color @commonVars 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "Repeated plan is not empty for $root`: $repeatOutput" }
    }
} catch {
    $failure = $_
} finally {
    if ($created) {
        $commonVars = @("-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
        foreach ($root in @($fleet, $foundation)) {
            if ((Test-Path $root) -and (Test-Path (Join-Path $root "terraform.tfstate"))) {
                $destroyOutput = (& terraform "-chdir=$root" destroy -auto-approve -input=false -no-color @commonVars 2>&1) -join "`n"
                if ($LASTEXITCODE -and -not $failure) { $failure = "E2E destroy failed for $root`: $destroyOutput" }
            }
        }
        try {
            $env:AWS_ACCESS_KEY_ID = "test"
            $env:AWS_SECRET_ACCESS_KEY = "test"
            foreach ($region in @("us-east-1", "us-west-2")) {
                $vpcs = Invoke-AwsJson @("--endpoint-url", $LocalstackEndpoint, "--region", $region, "ec2", "describe-vpcs", "--filters", "Name=tag:RunId,Values=$runId")
                $templates = Invoke-AwsJson @("--endpoint-url", $LocalstackEndpoint, "--region", $region, "ec2", "describe-launch-templates")
                $instances = Invoke-AwsJson @("--endpoint-url", $LocalstackEndpoint, "--region", $region, "ec2", "describe-instances", "--filters", "Name=tag:RunId,Values=$runId", "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down")
                $matchingTemplates = @($templates.LaunchTemplates | Where-Object { $_.LaunchTemplateName -like "$runId-*" })
                $activeInstances = @($instances.Reservations | ForEach-Object { $_.Instances })
                if (@($vpcs.Vpcs).Count -or $matchingTemplates.Count -or $activeInstances.Count) {
                    if (-not $failure) { $failure = "LocalStack residual resources remain in $region for $runId" }
                }
            }
            $roleRaw = (& aws --endpoint-url $LocalstackEndpoint --region us-east-1 iam get-role --role-name "$runId-compute-role" --output json 2>&1) -join "`n"
            if ($LASTEXITCODE -eq 0 -and -not $failure) { $failure = "LocalStack IAM role residual remains for $runId" }
        } catch {
            if (-not $failure) { $failure = $_ }
        }
    }
    $env:AWS_ACCESS_KEY_ID = $oldAccess
    $env:AWS_SECRET_ACCESS_KEY = $oldSecret
    $env:AWS_DEFAULT_REGION = $oldRegion
    $resolved = [IO.Path]::GetFullPath($temp)
    if ($resolved.StartsWith([IO.Path]::GetFullPath($tempBase), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf).StartsWith("tfpro-c35-")) {
        if (Test-Path -LiteralPath $resolved) {
            try {
                Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
            } catch {
                if (-not $failure) { $failure = "Failed to remove isolated grader directory $resolved`: $_" }
                else { Write-Warning "Additional cleanup failure for $resolved`: $_" }
            }
        }
    } elseif (Test-Path -LiteralPath $temp) {
        if (-not $failure) { $failure = "Refusing to remove an unsafe grader path: $temp" }
        else { Write-Warning "Unsafe grader path was not removed: $temp" }
    }
}
if ($failure) { throw $failure }
Write-Host "PASS: Challenge 35 canonical contracts, saved plans, drift recovery, and LocalStack dual-state E2E verified."
