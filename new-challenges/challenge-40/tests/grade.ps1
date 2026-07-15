param(
    [string]$Candidate = (Join-Path $PSScriptRoot "../starter"),
    [string]$LocalstackEndpoint = "http://localhost:4566"
)

$ErrorActionPreference = "Stop"

function Assert-LoopbackEndpoint([string]$Endpoint) {
    $uri = $null
    # Raw-origin validation intentionally runs before Candidate resolution,
    # filesystem reads, health probes, Terraform, or AWS network activity.
    if ([string]::IsNullOrEmpty($Endpoint) -or $Endpoint.IndexOf([char]13) -ge 0 -or $Endpoint.IndexOf([char]10) -ge 0) {
        throw "LocalstackEndpoint must not contain CR or LF characters."
    }
    $endpointMatch = [regex]::Match(
        $Endpoint,
        '\Ahttps?://(?:localhost|127\.0\.0\.1|\[::1\]):(?<port>[1-9][0-9]{0,4})\z',
        [Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $endpointMatch.Success -or [int]$endpointMatch.Groups['port'].Value -gt 65535 -or
        -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @("http", "https") -or
        $uri.DnsSafeHost -notin @("localhost", "127.0.0.1", "::1") -or
        $uri.Port -lt 1 -or
        $uri.Port -ne [int]$endpointMatch.Groups['port'].Value -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        $uri.PathAndQuery -ne "/") {
        throw "LocalstackEndpoint must be an HTTP(S) loopback root origin with an explicit port from 1 to 65535."
    }
}

function Copy-CleanTree([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in @(".terraform", ".terraform.lock.hcl", "terraform.tfstate", "terraform.tfstate.backup", ".terraform.tfstate.lock.info") -or
            $item.Name -like "tests-generated*" -or $item.Extension -in @(".tfplan", ".tfstate")) {
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
        } elseif ($state -eq "string") {
            [void]$builder.Append($current)
            if ($current -eq '\' -and $i + 1 -lt $Text.Length) { $i++; [void]$builder.Append($Text[$i]) }
            elseif ($current -eq '"') { $state = "code" }
        } elseif ($state -eq "line") {
            if ($current -eq "`n") { [void]$builder.Append($current); $state = "code" } else { [void]$builder.Append(' ') }
        } else {
            if ($current -eq '*' -and $next -eq '/') { [void]$builder.Append("  "); $i++; $state = "code" }
            elseif ($current -eq "`n") { [void]$builder.Append($current) } else { [void]$builder.Append(' ') }
        }
    }
    return $builder.ToString()
}

function Test-HclHeredocOpener([string]$Text) {
    $contexts = [Collections.Generic.List[object]]::new()
    [void]$contexts.Add([pscustomobject]@{ Kind = 'code'; Depth = 0 })
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $current = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
        $nextNext = if ($i + 2 -lt $Text.Length) { $Text[$i + 2] } else { [char]0 }
        $context = $contexts[$contexts.Count - 1]

        if ($context.Kind -eq 'string') {
            if ($current -eq '\') { $i++; continue }
            if (($current -eq '$' -or $current -eq '%') -and $next -eq $current -and $nextNext -eq '{') {
                $i += 2
                continue
            }
            if (($current -eq '$' -or $current -eq '%') -and $next -eq '{') {
                [void]$contexts.Add([pscustomobject]@{ Kind = 'template'; Depth = 1 })
                $i++
                continue
            }
            if ($current -eq '"') { $contexts.RemoveAt($contexts.Count - 1) }
            continue
        }

        if ($current -eq '"') {
            [void]$contexts.Add([pscustomobject]@{ Kind = 'string'; Depth = 0 })
            continue
        }
        if ($current -eq '<' -and $next -eq '<') {
            $marker = $i + 2
            if ($marker -lt $Text.Length -and $Text[$marker] -eq '-') { $marker++ }
            if ($marker -lt $Text.Length -and ([char]::IsLetter($Text[$marker]) -or $Text[$marker] -eq '_')) {
                return $true
            }
        }
        if ($context.Kind -eq 'template') {
            if ($current -eq '{') { $context.Depth++ }
            elseif ($current -eq '}') {
                $context.Depth--
                if ($context.Depth -eq 0) { $contexts.RemoveAt($contexts.Count - 1) }
            }
        }
    }
    return $false
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
                if ($depth -eq 0) { $blocks.Add($Text.Substring($match.Index, $i - $match.Index + 1)); break }
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

function ConvertTo-CompactHcl([string]$Text) {
    return [regex]::Replace($Text, '[ \t\r\n]+', '')
}

function Assert-ExactStringSet([string[]]$Actual, [string[]]$Expected, [string]$Context) {
    $actualSorted = @($Actual | Sort-Object)
    $expectedSorted = @($Expected | Sort-Object)
    if ($actualSorted.Count -ne $expectedSorted.Count -or
        ($actualSorted -join '|') -cne ($expectedSorted -join '|')) {
        throw "$Context must be exactly [$($expectedSorted -join ', ')]; found [$($actualSorted -join ', ')]."
    }
}

function Assert-ExactOneLabelBlocks([string]$Text, [string]$Kind, [string[]]$Expected, [string]$Context) {
    $pattern = '(?m)^[ \t]*' + [regex]::Escape($Kind) + '\s+"(?<name>[^"]+)"\s*\{'
    $actual = @([regex]::Matches($Text, $pattern) | ForEach-Object { $_.Groups['name'].Value })
    Assert-ExactStringSet $actual $Expected $Context
}

function Assert-ExactTwoLabelBlocks([string]$Text, [string]$Kind, [string[]]$Expected, [string]$Context) {
    $pattern = '(?m)^[ \t]*' + [regex]::Escape($Kind) + '\s+"(?<type>[^"]+)"\s+"(?<name>[^"]+)"\s*\{'
    $actual = @([regex]::Matches($Text, $pattern) | ForEach-Object { "$($_.Groups['type'].Value).$($_.Groups['name'].Value)" })
    Assert-ExactStringSet $actual $Expected $Context
}

function Assert-ExactBareBlockCount([string]$Text, [string]$Kind, [int]$Expected, [string]$Context) {
    $pattern = '(?m)^[ \t]*' + [regex]::Escape($Kind) + '\s*\{'
    $actual = [regex]::Matches($Text, $pattern).Count
    if ($actual -ne $Expected) { throw "$Context must contain exactly $Expected $Kind block(s); found $actual." }
}

function Get-GuardCondition([string]$Block, [string]$Context) {
    $compact = ConvertTo-CompactHcl $Block
    $matches = @([regex]::Matches($compact, '\Aprecondition\{condition=(?<condition>.*?)error_message="[^"]*"\}\z'))
    if ($matches.Count -ne 1) { throw "$Context must have exactly one condition followed by one literal error_message." }
    return $matches[0].Groups['condition'].Value
}

function Assert-ExactGuardTaxonomy([string[]]$Blocks, [Collections.IDictionary]$ExpectedConditions, [string]$Context) {
    if ($Blocks.Count -ne $ExpectedConditions.Count) {
        throw "$Context must contain exactly $($ExpectedConditions.Count) semantic guard classes."
    }
    $seen = [Collections.Generic.List[string]]::new()
    foreach ($block in $Blocks) {
        $condition = Get-GuardCondition $block $Context
        if ($condition -match '\|\|' -or $condition -match '(?<![A-Za-z0-9_])true(?![A-Za-z0-9_])') {
            throw "$Context guards must not use OR, naked true, or catch-all conditions."
        }
        $classes = @($ExpectedConditions.Keys | Where-Object { $condition -ceq $ExpectedConditions[$_] })
        if ($classes.Count -ne 1) {
            throw "$Context contains an incomplete, combined, empty-shell, or unclassified guard: $condition"
        }
        [void]$seen.Add([string]$classes[0])
    }
    Assert-ExactStringSet @($seen) @($ExpectedConditions.Keys) "$Context semantic guard classes"
}

function Assert-ProviderBlock([string]$Block, [string]$RegionPattern, [string[]]$Services, [string]$Context, [bool]$RequirePathStyle) {
    Assert-ExactAssignment $Block 'region' $RegionPattern $Context
    Assert-ExactAssignment $Block 'access_key' '"test"' $Context
    Assert-ExactAssignment $Block 'secret_key' '"test"' $Context
    foreach ($flag in @('skip_credentials_validation', 'skip_metadata_api_check', 'skip_requesting_account_id')) {
        Assert-ExactAssignment $Block $flag 'true' $Context
    }
    if ($RequirePathStyle) { Assert-ExactAssignment $Block 's3_use_path_style' 'true' $Context }
    foreach ($forbidden in @('profile', 'token', 'shared_config_files', 'shared_credentials_files', 'web_identity_token_file')) {
        if ([regex]::Matches($Block, '(?m)^[ \t]*' + [regex]::Escape($forbidden) + '\s*=').Count) { throw "$Context must not use $forbidden." }
    }
    if ($Block -match '(?m)^[ \t]*(?:assume_role|assume_role_with_web_identity)\s*\{') { throw "$Context must not use alternate credential blocks." }
    $endpointBlocks = @(Get-HclBlocks $Block '(?m)^[ \t]*endpoints\s*\{')
    if ($endpointBlocks.Count -ne 1) { throw "$Context must contain exactly one endpoints block." }
    $endpointBlock = $endpointBlocks[0]
    foreach ($service in $Services) { Assert-ExactAssignment $endpointBlock $service 'var\.localstack_endpoint' $Context }
    $actualKeys = @([regex]::Matches($endpointBlock, '(?m)^[ \t]*(?<key>[a-z0-9_]+)\s*=') | ForEach-Object { $_.Groups['key'].Value })
    if ($actualKeys.Count -ne $Services.Count -or (Compare-Object ($actualKeys | Sort-Object) ($Services | Sort-Object))) {
        throw "$Context endpoints must exactly match: $($Services -join ', ')."
    }
}

function Assert-ExactPlanChanges([string]$Root, [string]$PlanPath, [hashtable]$Expected, [string]$Context) {
    $raw = (& terraform "-chdir=$Root" show -json $PlanPath 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Could not render $Context plan JSON: $raw" }
    $plan = $raw | ConvertFrom-Json -Depth 100
    $changes = @($plan.resource_changes | Where-Object { $_.mode -eq 'managed' -and (@($_.change.actions) -join ',') -ne 'no-op' })
    if ($changes.Count -ne $Expected.Count) {
        throw "$Context expected $($Expected.Count) managed changes but saw $($changes.Count): $($changes.address -join ', ')"
    }
    foreach ($change in $changes) {
        if (-not $Expected.ContainsKey($change.address)) { throw "$Context contains an unapproved address: $($change.address)" }
        $actual = @($change.change.actions) -join ','
        if ($actual -ne $Expected[$change.address]) { throw "$Context action mismatch for $($change.address): $actual" }
    }
    return $plan
}

function Invoke-AwsJson([string[]]$Arguments) {
    $raw = (& aws @Arguments --output json 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "AWS CLI failed: aws $($Arguments -join ' ')`n$raw" }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json -Depth 100
}

function Convert-TagsToMap($Tags) {
    $map = @{}
    foreach ($tag in @($Tags)) { $map[$tag.Key] = $tag.Value }
    return $map
}

function Invoke-CleanupStep([Collections.Generic.List[string]]$Errors, [string]$Label, [scriptblock]$Action) {
    try {
        & $Action
    } catch {
        [void]$Errors.Add("$Label`: $($_.Exception.Message)")
    }
}

function Invoke-CleanupQuery([Collections.Generic.List[string]]$Errors, [string]$Label, [scriptblock]$Action) {
    try {
        return (& $Action)
    } catch {
        [void]$Errors.Add("$Label`: $($_.Exception.Message)")
        return $null
    }
}

# This is intentionally the first action with observable external effects.
Assert-LoopbackEndpoint $LocalstackEndpoint

$LabRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CandidateRoot = (Resolve-Path $Candidate).Path
$artifactRoot = Join-Path $CandidateRoot 'artifact'
$runtimeRoot = Join-Path $CandidateRoot 'runtime'
$childRoot = Join-Path $runtimeRoot 'modules/regional'
foreach ($root in @($artifactRoot, $runtimeRoot, $childRoot)) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Candidate is missing required directory: $root" }
}

$allowedTfDirectories = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($root in @($artifactRoot, $runtimeRoot, $childRoot)) {
    [void]$allowedTfDirectories.Add([IO.Path]::GetFullPath($root))
}
$candidateTfFiles = @(Get-ChildItem -LiteralPath $CandidateRoot -Recurse -File -Filter *.tf -Force)
foreach ($file in $candidateTfFiles) {
    $directory = [IO.Path]::GetFullPath($file.DirectoryName)
    if (-not $allowedTfDirectories.Contains($directory)) {
        throw "Candidate contains Terraform outside an allowed HCL directory: $($file.FullName)"
    }
}
$candidateJsonConfigs = @(Get-ChildItem -LiteralPath $CandidateRoot -Recurse -File -Filter *.tf.json -Force)
if ($candidateJsonConfigs.Count) {
    throw "Terraform JSON configuration is prohibited; use only the audited .tf roots: $($candidateJsonConfigs.FullName -join ', ')"
}

$artifactSource = Remove-HclComments (((Get-ChildItem $artifactRoot -File -Filter *.tf) | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n")
$runtimeSource = Remove-HclComments (((Get-ChildItem $runtimeRoot -File -Filter *.tf) | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n")
$childSource = Remove-HclComments (((Get-ChildItem $childRoot -File -Filter *.tf) | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n")

foreach ($entry in @(
        @{ Source = $artifactSource; Name = 'artifact' },
        @{ Source = $runtimeSource; Name = 'runtime' },
        @{ Source = $childSource; Name = 'regional child' }
    )) {
    if (Test-HclHeredocOpener $entry.Source) {
        throw "$($entry.Name) must not use heredoc syntax; it is prohibited by this audited lab grammar."
    }
}

Assert-ExactBareBlockCount $artifactSource 'terraform' 1 'artifact root'
Assert-ExactBareBlockCount $artifactSource 'locals' 1 'artifact root'
Assert-ExactOneLabelBlocks $artifactSource 'provider' @('aws') 'artifact provider blocks'
Assert-ExactOneLabelBlocks $artifactSource 'variable' @('aws_region', 'localstack_endpoint', 'manifest_path', 'run_id') 'artifact variables'
Assert-ExactOneLabelBlocks $artifactSource 'output' @('object_ids', 'release_contract') 'artifact outputs'
Assert-ExactTwoLabelBlocks $artifactSource 'resource' @('aws_s3_bucket.release', 'aws_s3_object.artifact', 'terraform_data.manifest_guard') 'artifact resources'
Assert-ExactTwoLabelBlocks -Text $artifactSource -Kind 'data' -Expected @() -Context 'artifact data blocks'
Assert-ExactOneLabelBlocks -Text $artifactSource -Kind 'module' -Expected @() -Context 'artifact modules'
Assert-ExactOneLabelBlocks -Text $artifactSource -Kind 'check' -Expected @() -Context 'artifact checks'

Assert-ExactBareBlockCount $runtimeSource 'terraform' 1 'runtime root'
Assert-ExactBareBlockCount $runtimeSource 'locals' 1 'runtime root'
Assert-ExactOneLabelBlocks $runtimeSource 'provider' @('aws', 'aws') 'runtime provider blocks'
Assert-ExactOneLabelBlocks $runtimeSource 'variable' @('artifact_state_path', 'dr_region', 'localstack_endpoint', 'primary_region', 'run_id', 'runtime_catalog_path') 'runtime variables'
Assert-ExactOneLabelBlocks $runtimeSource 'output' @('ami_ids', 'fleet_keys', 'release_version', 'replica_ids', 'runtime_contracts') 'runtime outputs'
Assert-ExactTwoLabelBlocks $runtimeSource 'data' @('aws_ami.dr', 'aws_ami.primary', 'aws_subnets.dr', 'aws_subnets.primary', 'aws_vpc.dr', 'aws_vpc.primary', 'terraform_remote_state.artifact') 'runtime data blocks'
Assert-ExactTwoLabelBlocks $runtimeSource 'resource' @('aws_iam_instance_profile.runtime', 'aws_iam_role.runtime', 'terraform_data.contract_guard') 'runtime resources'
Assert-ExactOneLabelBlocks $runtimeSource 'module' @('dr', 'primary') 'runtime modules'
Assert-ExactOneLabelBlocks -Text $runtimeSource -Kind 'check' -Expected @() -Context 'runtime checks'

Assert-ExactBareBlockCount $childSource 'terraform' 1 'regional child'
Assert-ExactBareBlockCount $childSource 'locals' 1 'regional child'
Assert-ExactOneLabelBlocks -Text $childSource -Kind 'provider' -Expected @() -Context 'regional child providers'
Assert-ExactOneLabelBlocks $childSource 'variable' @('ami_id', 'fleets', 'instance_profile_name', 'region', 'release_contract', 'role', 'run_id', 'subnet_id', 'vpc_id') 'regional child variables'
Assert-ExactOneLabelBlocks $childSource 'output' @('replica_ids', 'runtime_contracts') 'regional child outputs'
Assert-ExactTwoLabelBlocks $childSource 'resource' @('aws_instance.replica', 'aws_launch_template.fleet', 'aws_security_group.runtime', 'terraform_data.release_revision') 'regional child resources'
Assert-ExactTwoLabelBlocks -Text $childSource -Kind 'data' -Expected @() -Context 'regional child data blocks'
Assert-ExactOneLabelBlocks -Text $childSource -Kind 'module' -Expected @() -Context 'regional child modules'
Assert-ExactOneLabelBlocks -Text $childSource -Kind 'check' -Expected @() -Context 'regional child checks'

foreach ($entry in @(
        @{ Source = $artifactSource; Name = 'artifact' },
        @{ Source = $runtimeSource; Name = 'runtime' },
        @{ Source = $childSource; Name = 'regional child' }
    )) {
    foreach ($kind in @('import', 'moved', 'removed')) {
        Assert-ExactBareBlockCount $entry.Source $kind 0 $entry.Name
    }
}

foreach ($entry in @(@{ Source = $artifactSource; Name = 'artifact' }, @{ Source = $runtimeSource; Name = 'runtime' })) {
    $variable = Get-OneHclBlock $entry.Source '(?m)^[ \t]*variable\s+"localstack_endpoint"\s*\{' "$($entry.Name) localstack_endpoint"
    Assert-ExactAssignment $variable 'default' '"http://localhost:4566"' "$($entry.Name) localstack_endpoint"
    $validations = @(Get-HclBlocks $variable '(?m)^[ \t]*validation\s*\{')
    if ($validations.Count -ne 1) { throw "$($entry.Name) localstack_endpoint needs exactly one strict validation block." }
    $expectedValidation = @'
validation {
  condition = (
    can(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)) &&
    try(tonumber(regex("^https?://(localhost|127\\.0\\.0\\.1|\\[::1\\]):([1-9][0-9]{0,4})\\z", var.localstack_endpoint)[1]) <= 65535, false)
  )
  error_message = "localstack_endpoint must be a loopback HTTP(S) origin with an explicit port from 1 to 65535."
}
'@
    if ((ConvertTo-CompactHcl $validations[0]) -cne (ConvertTo-CompactHcl $expectedValidation)) {
        throw "$($entry.Name) localstack_endpoint validation must be the exact loopback root-origin, CR/LF-safe, port-bounded expression."
    }
}

$artifactProviders = @(Get-HclBlocks $artifactSource '(?m)^[ \t]*provider\s+"aws"\s*\{')
if ($artifactProviders.Count -ne 1 -or $artifactProviders[0] -match '(?m)^[ \t]*alias\s*=') { throw 'Artifact root needs exactly one unaliased AWS provider.' }
Assert-ProviderBlock $artifactProviders[0] 'var\.aws_region' @('s3', 'sts') 'artifact provider' $true

$runtimeProviders = @(Get-HclBlocks $runtimeSource '(?m)^[ \t]*provider\s+"aws"\s*\{')
if ($runtimeProviders.Count -ne 2) { throw 'Runtime root needs exactly two AWS provider blocks.' }
$defaultProviders = @($runtimeProviders | Where-Object { $_ -notmatch '(?m)^[ \t]*alias\s*=' })
$drProviders = @($runtimeProviders | Where-Object { [regex]::Matches($_, '(?m)^[ \t]*alias\s*=\s*"dr"\s*$').Count -eq 1 })
if ($defaultProviders.Count -ne 1 -or $drProviders.Count -ne 1) { throw 'Runtime needs one default and one aws.dr provider.' }
Assert-ProviderBlock $defaultProviders[0] 'var\.primary_region' @('ec2', 'iam', 'sts') 'runtime default provider' $false
Assert-ProviderBlock $drProviders[0] 'var\.dr_region' @('ec2', 'iam', 'sts') 'runtime dr provider' $false
if ((Get-HclBlocks $childSource '(?m)^[ \t]*provider\s+"aws"\s*\{').Count) { throw 'Regional child module must receive its provider from the caller.' }

$allSource = "$artifactSource`n$runtimeSource`n$childSource"
if ([regex]::Matches($allSource, 'required_version\s*=\s*"~>\s*1\.6"').Count -ne 3 -or
    [regex]::Matches($allSource, 'version\s*=\s*"~>\s*5\.100"').Count -ne 3) {
    throw 'Both roots and the child module must pin Terraform ~> 1.6 and AWS provider ~> 5.100.'
}
if ($allSource -match '(?i)autoscaling') { throw 'Challenge 40 must not call Auto Scaling APIs.' }

$artifactMain = Remove-HclComments (Get-Content -Raw (Join-Path $artifactRoot 'main.tf'))
$artifactOutputs = Remove-HclComments (Get-Content -Raw (Join-Path $artifactRoot 'outputs.tf'))
$runtimeMain = Remove-HclComments (Get-Content -Raw (Join-Path $runtimeRoot 'main.tf'))
$childMain = Remove-HclComments (Get-Content -Raw (Join-Path $childRoot 'main.tf'))

if ($artifactMain -notmatch 'artifacts_by_name\s*=\s*\{' -or $artifactMain -notmatch 'artifact\.name\s*=>\s*artifact\.\.\.' -or
    $artifactMain -notmatch 'duplicate_names\s*=\s*\[' -or $artifactMain -notmatch 'sha256\(file\(artifact\.source_path\)\)\s*==\s*artifact\.sha256') {
    throw 'Artifact manifest must use grouped stable identities, duplicate detection, and real digest verification.'
}
$manifestGuard = Get-OneHclBlock $artifactMain '(?m)^[ \t]*resource\s+"terraform_data"\s+"manifest_guard"\s*\{' 'artifact manifest guard'
$manifestPreconditions = @(Get-HclBlocks $manifestGuard '(?m)^[ \t]*precondition\s*\{')
$manifestGuardTaxonomy = [ordered]@{
    schema              = 'try(local.manifest.schema_version,"")=="release-manifest/v1"'
    contract            = 'try(local.manifest.contract_version,0)==1'
    release             = 'can(regex("^[0-9]{4}\\.[0-9]{2}\\.[0-9]+$",try(local.manifest.release_version,"")))'
    cardinality_unique  = 'length(local.artifact_rows)>=1&&length(local.artifact_rows)<=8&&length(local.duplicate_names)==0'
    field_path_digest   = 'alltrue([forartifactinlocal.artifact_rows:can(regex("^[a-z][a-z0-9-]{1,30}$",artifact.name))&&can(regex("^releases/[a-z0-9-]+/[a-zA-Z0-9._-]+$",artifact.key))&&startswith(replace(artifact.source_path,"\\","/"),"' + '$' + '{replace(local.manifest_dir,"\\","/")}/")&&fileexists(artifact.source_path)&&can(regex("^[0-9a-f]{64}$",artifact.sha256))])'
    payload_digest      = 'alltrue([forartifactinlocal.artifact_rows:fileexists(artifact.source_path)&&sha256(file(artifact.source_path))==artifact.sha256])'
}
Assert-ExactGuardTaxonomy $manifestPreconditions $manifestGuardTaxonomy 'artifact manifest guard'
$objectBlock = Get-OneHclBlock $artifactMain '(?m)^[ \t]*resource\s+"aws_s3_object"\s+"artifact"\s*\{' 'artifact objects'
Assert-ExactAssignment $objectBlock 'for_each' 'local\.artifacts' 'artifact objects'
if ($objectBlock -match '(?m)^[ \t]*ignore_changes\s*=') { throw 'S3 artifact objects must not ignore any changes.' }
foreach ($token in @('ArtifactName', 'ArtifactDigest', 'ReleaseVersion', 'RunId')) { if ($objectBlock -notmatch [regex]::Escape($token)) { throw "S3 objects are missing $token tracking." } }
foreach ($token in @('contract_version\s*=\s*1', 'release_version', 'bucket_name', 'region', 'artifacts', 'sha256')) {
    if ($artifactOutputs -notmatch $token) { throw "release_contract is missing required field pattern: $token" }
}

$amiDr = Get-OneHclBlock $runtimeMain '(?m)^[ \t]*data\s+"aws_ami"\s+"dr"\s*\{' 'runtime aws_ami.dr'
$vpcDr = Get-OneHclBlock $runtimeMain '(?m)^[ \t]*data\s+"aws_vpc"\s+"dr"\s*\{' 'runtime aws_vpc.dr'
$subnetsDr = Get-OneHclBlock $runtimeMain '(?m)^[ \t]*data\s+"aws_subnets"\s+"dr"\s*\{' 'runtime aws_subnets.dr'
foreach ($entry in @($amiDr, $vpcDr, $subnetsDr)) { Assert-ExactAssignment $entry 'provider' 'aws\.dr' 'DR data source' }
$primaryModule = Get-OneHclBlock $runtimeMain '(?m)^[ \t]*module\s+"primary"\s*\{' 'runtime primary module'
$drModule = Get-OneHclBlock $runtimeMain '(?m)^[ \t]*module\s+"dr"\s*\{' 'runtime dr module'
Assert-ExactAssignment $primaryModule 'source' '"\./modules/regional"' 'primary module'
Assert-ExactAssignment $drModule 'source' '"\./modules/regional"' 'dr module'
Assert-ExactAssignment $primaryModule 'providers' '\{\s*aws\s*=\s*aws\s*\}' 'primary module'
Assert-ExactAssignment $drModule 'providers' '\{\s*aws\s*=\s*aws\.dr\s*\}' 'dr module'
if ($runtimeMain -notmatch 'data\s+"terraform_remote_state"\s+"artifact"' -or
    $runtimeMain -notmatch '"\$\{trimspace\(try\(row\.name,\s*""\)\)\}@\$\{trimspace\(try\(row\.location,\s*""\)\)\}"' -or
    $runtimeMain -notmatch 'fleet\.key\s*=>\s*fleet\.\.\.') {
    throw 'Runtime must consume remote state and group stable name@location identities.'
}
$contractGuard = Get-OneHclBlock $runtimeMain '(?m)^[ \t]*resource\s+"terraform_data"\s+"contract_guard"\s*\{' 'runtime contract guard'
$contractPreconditions = @(Get-HclBlocks $contractGuard '(?m)^[ \t]*precondition\s*\{')
$runtimeGuardTaxonomy = [ordered]@{
    contract             = 'try(local.release_contract.contract_version,0)==1'
    region               = 'try(local.release_contract.region,"")==var.primary_region'
    release              = 'can(regex("^[0-9]{4}\\.[0-9]{2}\\.[0-9]+$",try(local.release_contract.release_version,"")))'
    bucket               = 'try(local.release_contract.bucket_name,"")=="' + '$' + '{var.run_id}-release-artifacts"'
    artifact_key         = 'alltrue([forartifactinvalues(try(local.release_contract.artifacts,{})):can(regex("^releases/[a-z0-9-]+/[A-Za-z0-9._-]+$",try(artifact.key,"")))&&!startswith(try(artifact.key,""),"/")&&!strcontains(try(artifact.key,""),"../")&&!strcontains(try(artifact.key,""),"\\")])'
    artifact_digest      = 'alltrue([forartifactinvalues(try(local.release_contract.artifacts,{})):can(regex("^[0-9a-f]{64}$",try(artifact.sha256,"")))])'
    catalog_schema       = 'try(local.catalog.schema_version,"")=="runtime-catalog/v1"'
    catalog_count        = 'length(local.catalog_rows)>=1&&length(local.catalog_rows)<=6'
    fleet_duplicates     = 'length(local.duplicate_fleet_keys)==0'
    fleet_fields         = 'alltrue([forfleetinlocal.catalog_rows:can(regex("^[a-z][a-z0-9-]{1,24}$",fleet.name))&&contains(["primary","dr"],fleet.location)&&can(regex("^[a-z][a-z0-9-]{1,30}$",fleet.artifact))&&contains(["t3.micro","t3.small"],fleet.instance_type)&&fleet.replicas>=1&&fleet.replicas<=3])'
    artifact_membership  = 'alltrue([forfleetinlocal.catalog_rows:contains(keys(try(local.release_contract.artifacts,{})),fleet.artifact)])'
}
Assert-ExactGuardTaxonomy $contractPreconditions $runtimeGuardTaxonomy 'runtime contract guard'
$bucketGuards = @($contractPreconditions | Where-Object {
        $_ -match 'try\(local\.release_contract\.bucket_name,\s*""\)\s*==\s*"\$\{var\.run_id\}-release-artifacts"'
    })
$keyGuards = @($contractPreconditions | Where-Object {
        $_.Contains('can(regex("^releases/[a-z0-9-]+/[A-Za-z0-9._-]+$", try(artifact.key, "")))') -and
        $_.Contains('!startswith(try(artifact.key, ""), "/")') -and
        $_.Contains('!strcontains(try(artifact.key, ""), "../")') -and
        $_.Contains('!strcontains(try(artifact.key, ""), "\\")')
    })
$digestGuards = @($contractPreconditions | Where-Object {
        $_.Contains('can(regex("^[0-9a-f]{64}$", try(artifact.sha256, "")))')
    })
if ($bucketGuards.Count -ne 1 -or $keyGuards.Count -ne 1 -or $digestGuards.Count -ne 1) {
    throw 'Runtime contract guard needs exact bucket ownership, safe releases/... keys, and lowercase sha256 guards.'
}
$newGuardBlocks = @($bucketGuards[0], $keyGuards[0], $digestGuards[0])
if (@($newGuardBlocks | Select-Object -Unique).Count -ne 3) {
    throw 'Bucket, artifact-key, and digest checks must be three independent preconditions.'
}
$profileBlock = Get-OneHclBlock $runtimeMain '(?m)^[ \t]*resource\s+"aws_iam_instance_profile"\s+"runtime"\s*\{' 'runtime instance profile'
foreach ($token in @('RunId', 'Lab', 'ManagedBy')) { if ($profileBlock -notmatch $token) { throw "IAM instance profile is missing $token tracking." } }

$launchTemplate = Get-OneHclBlock $childMain '(?m)^[ \t]*resource\s+"aws_launch_template"\s+"fleet"\s*\{' 'regional launch template'
$revision = Get-OneHclBlock $childMain '(?m)^[ \t]*resource\s+"terraform_data"\s+"release_revision"\s*\{' 'regional release revision'
$replica = Get-OneHclBlock $childMain '(?m)^[ \t]*resource\s+"aws_instance"\s+"replica"\s*\{' 'regional replica'
$templateLifecycle = Get-OneHclBlock $launchTemplate '(?m)^[ \t]*lifecycle\s*\{' 'launch template lifecycle'
$replicaLifecycle = Get-OneHclBlock $replica '(?m)^[ \t]*lifecycle\s*\{' 'replica lifecycle'
Assert-ExactAssignment $templateLifecycle 'ignore_changes' '\[tag_specifications\]' 'launch template lifecycle'
Assert-ExactAssignment $replicaLifecycle 'ignore_changes' '\[launch_template\]' 'replica lifecycle'
Assert-ExactAssignment $replicaLifecycle 'replace_triggered_by' '\[terraform_data\.release_revision\[each\.key\]\]' 'replica lifecycle'
if ([regex]::Matches($allSource, '(?m)^[ \t]*ignore_changes\s*=').Count -ne 2) {
    throw 'Only launch-template tag_specifications and instance launch_template may use ignore_changes.'
}
foreach ($token in @('contract_version', 'release_version', 'bucket_name', 'artifact_name', 'artifact_key', 'artifact_sha256')) {
    if ($launchTemplate -notmatch [regex]::Escape($token)) { throw "Launch template user data is missing $token." }
}
foreach ($token in @('release_version', 'artifact_digest', 'template_id', 'template_version', 'latest_version')) {
    if ($revision -notmatch [regex]::Escape($token)) { throw "Release revision sentinel is missing $token." }
}
foreach ($token in @('Fleet', 'Replica', 'Role', 'Region', 'ArtifactName', 'ArtifactKey', 'ArtifactDigest', 'ReleaseVersion', 'RunId', 'Lab', 'ManagedBy')) {
    if ($replica -notmatch [regex]::Escape($token)) { throw "Replica tags are missing $token." }
}
if ($childMain -notmatch '"\$\{fleet_key\}#\$\{format\("%02d",\s*index\s*\+\s*1\)\}"') { throw 'Replica identity must be name@location#NN.' }

$health = Invoke-RestMethod -Uri "$LocalstackEndpoint/_localstack/health" -TimeoutSec 5
foreach ($service in @('s3', 'ec2', 'iam', 'sts')) {
    if ($health.services.$service -notin @('available', 'running')) { throw "LocalStack $service is unavailable." }
}

$tempBase = [IO.Path]::GetTempPath()
$temp = Join-Path $tempBase ("tfpro-c40-" + [guid]::NewGuid().ToString('N'))
$workRoot = Join-Path $temp 'candidate'
$artifact = Join-Path $workRoot 'artifact'
$runtime = Join-Path $workRoot 'runtime'
$fixtures = Join-Path $temp 'fixtures'
$runId = 'c40' + [guid]::NewGuid().ToString('N').Substring(0, 10)
$failure = $null
$created = $false
$oldAccess = $env:AWS_ACCESS_KEY_ID
$oldSecret = $env:AWS_SECRET_ACCESS_KEY
$oldRegion = $env:AWS_DEFAULT_REGION
try {
    New-Item -ItemType Directory -Path $temp | Out-Null
    Copy-CleanTree $CandidateRoot $workRoot
    Copy-CleanTree (Join-Path $LabRoot 'fixtures') $fixtures
    $created = $true

    foreach ($case in @(
        @{ Root = $artifact; File = 'artifact.tftest.hcl'; Passed = 7 },
        @{ Root = $runtime; File = 'runtime.tftest.hcl'; Passed = 16 }
    )) {
        $testName = "tests-generated-$PID"
        $testDir = Join-Path $case.Root $testName
        New-Item -ItemType Directory -Force $testDir | Out-Null
        Copy-Item (Join-Path $PSScriptRoot $case.File) $testDir -Force
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
            if ($LASTEXITCODE -or $summaryCount -ne 1 -or $runPassCount -ne $case.Passed) { throw "Canonical tests failed or exact run discovery changed for $($case.Root)." }
        } finally {
            Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $common = @("-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
    $artifactV1 = 'artifact-v1.tfplan'
    $output = (& terraform "-chdir=$artifact" plan -input=false -no-color "-out=$artifactV1" @common 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Artifact v1 plan failed: $output" }
    $artifactCreate = @{
        'terraform_data.manifest_guard'        = 'create'
        'aws_s3_bucket.release'                = 'create'
        'aws_s3_object.artifact["api"]'       = 'create'
        'aws_s3_object.artifact["worker"]'    = 'create'
    }
    $null = Assert-ExactPlanChanges $artifact $artifactV1 $artifactCreate 'artifact v1 delivery'
    $output = (& terraform "-chdir=$artifact" apply -input=false -no-color -auto-approve $artifactV1 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Artifact v1 saved-plan apply failed: $output" }

    $runtimeV1 = 'runtime-v1.tfplan'
    $output = (& terraform "-chdir=$runtime" plan -input=false -no-color "-out=$runtimeV1" @common 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Runtime v1 plan failed: $output" }
    $runtimeCreate = @{
        'terraform_data.contract_guard'                                  = 'create'
        'aws_iam_role.runtime'                                            = 'create'
        'aws_iam_instance_profile.runtime'                                = 'create'
        'module.primary.aws_security_group.runtime'                       = 'create'
        'module.dr.aws_security_group.runtime'                            = 'create'
        'module.primary.aws_launch_template.fleet["api@primary"]'        = 'create'
        'module.dr.aws_launch_template.fleet["worker@dr"]'               = 'create'
        'module.primary.terraform_data.release_revision["api@primary#01"]' = 'create'
        'module.dr.terraform_data.release_revision["worker@dr#01"]'      = 'create'
        'module.primary.aws_instance.replica["api@primary#01"]'          = 'create'
        'module.dr.aws_instance.replica["worker@dr#01"]'                 = 'create'
    }
    $null = Assert-ExactPlanChanges $runtime $runtimeV1 $runtimeCreate 'runtime v1 delivery'
    $output = (& terraform "-chdir=$runtime" apply -input=false -no-color -auto-approve $runtimeV1 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Runtime v1 saved-plan apply failed: $output" }

    $env:AWS_ACCESS_KEY_ID = 'test'
    $env:AWS_SECRET_ACCESS_KEY = 'test'
    $env:AWS_DEFAULT_REGION = 'us-east-1'

    $replicaRaw = (& terraform "-chdir=$runtime" output -json replica_ids 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Could not read v1 replica IDs: $replicaRaw" }
    $v1Ids = $replicaRaw | ConvertFrom-Json -AsHashtable
    if ($v1Ids.Count -ne 2 -or -not $v1Ids.ContainsKey('api@primary#01') -or -not $v1Ids.ContainsKey('worker@dr#01')) { throw 'Runtime must create exactly two stable replicas.' }

    $expectedV1 = @{
        api    = @{ Digest = '5b75c35286490e1c356eb9e6c2a49225231db2b169acb8bea07811b077b3a411'; Body = 'api release 1'; Key = 'releases/api/current.txt' }
        worker = @{ Digest = '155b7720a871a06a743222357f45a570ff91758d6307e2837d08390cf4b3e8d9'; Body = 'worker release 1'; Key = 'releases/worker/current.txt' }
    }
    $bucket = "$runId-release-artifacts"
    foreach ($name in @('api', 'worker')) {
        $bodyPath = Join-Path $temp "$name-v1.txt"
        $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'get-object', '--bucket', $bucket, '--key', $expectedV1[$name].Key, $bodyPath)
        if ((Get-Content -Raw $bodyPath).Trim() -ne $expectedV1[$name].Body) { throw "S3 $name v1 payload is wrong." }
        $tagResult = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'get-object-tagging', '--bucket', $bucket, '--key', $expectedV1[$name].Key)
        $tags = Convert-TagsToMap $tagResult.TagSet
        if ($tags.ArtifactName -ne $name -or $tags.ArtifactDigest -ne $expectedV1[$name].Digest -or $tags.ReleaseVersion -ne '2026.07.1' -or $tags.RunId -ne $runId) { throw "S3 $name v1 tags are wrong." }
    }

    $role = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'get-role', '--role-name', "$runId-runtime-role")
    $profile = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'get-instance-profile', '--instance-profile-name', "$runId-runtime-profile")
    $roleTags = Convert-TagsToMap $role.Role.Tags
    $profileTags = Convert-TagsToMap $profile.InstanceProfile.Tags
    foreach ($tags in @($roleTags, $profileTags)) {
        if ($tags.RunId -ne $runId -or $tags.Lab -ne 'challenge-40' -or $tags.ManagedBy -ne 'terraform') { throw 'IAM role/profile tracking tags are incomplete.' }
    }
    if (@($profile.InstanceProfile.Roles).Count -ne 1 -or $profile.InstanceProfile.Roles[0].RoleName -ne "$runId-runtime-role") { throw 'IAM instance profile is not linked to the runtime role.' }

    function Assert-RemoteRuntime([string]$Version, [hashtable]$Expected, [hashtable]$Ids) {
        $contractsRaw = (& terraform "-chdir=$runtime" output -json runtime_contracts 2>&1) -join "`n"
        if ($LASTEXITCODE) { throw "Could not read runtime contracts: $contractsRaw" }
        $contracts = $contractsRaw | ConvertFrom-Json -AsHashtable
        $amisRaw = (& terraform "-chdir=$runtime" output -json ami_ids 2>&1) -join "`n"
        if ($LASTEXITCODE) { throw "Could not read runtime AMIs: $amisRaw" }
        $amis = $amisRaw | ConvertFrom-Json -AsHashtable
        foreach ($fleetKey in @('api@primary', 'worker@dr')) {
            $name = if ($fleetKey.StartsWith('api@')) { 'api' } else { 'worker' }
            $replicaKey = "$fleetKey#01"
            $roleName = if ($fleetKey.EndsWith('@dr')) { 'dr' } else { 'primary' }
            $region = if ($roleName -eq 'dr') { 'us-west-2' } else { 'us-east-1' }
            $ami = if ($roleName -eq 'dr') { $amis.dr } else { $amis.primary }
            $contract = $contracts[$fleetKey]
            $instanceResult = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'describe-instances', '--instance-ids', $Ids[$replicaKey])
            $instances = @($instanceResult.Reservations | ForEach-Object { $_.Instances })
            if ($instances.Count -ne 1) { throw "$replicaKey was not visible in $region." }
            $instance = $instances[0]
            $instanceTags = Convert-TagsToMap $instance.Tags
            $templateResult = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'describe-launch-template-versions', '--launch-template-id', $contract.launch_template_id, '--versions', '$Latest')
            $template = $templateResult.LaunchTemplateVersions[0].LaunchTemplateData
            $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($template.UserData)) | ConvertFrom-Json -AsHashtable
            $templateInfo = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'describe-launch-templates', '--launch-template-ids', $contract.launch_template_id)
            $templateTags = Convert-TagsToMap $templateInfo.LaunchTemplates[0].Tags
            $sgResult = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'describe-security-groups', '--group-ids', $template.SecurityGroupIds[0])
            $sgTags = Convert-TagsToMap $sgResult.SecurityGroups[0].Tags
            if ($contract.role -ne $roleName -or $contract.region -ne $region -or $contract.release_version -ne $Version -or
                $contract.artifact_name -ne $name -or $contract.artifact_key -ne $Expected[$name].Key -or $contract.artifact_digest -ne $Expected[$name].Digest -or
                @($contract.instance_ids) -notcontains $Ids[$replicaKey] -or $template.ImageId -ne $ami -or $template.InstanceType -ne 't3.micro' -or
                @($template.SecurityGroupIds).Count -ne 1 -or $template.IamInstanceProfile.Name -ne "$runId-runtime-profile" -or
                $decoded.contract_version -ne 1 -or $decoded.release_version -ne $Version -or $decoded.bucket_name -ne $bucket -or
                $decoded.artifact_name -ne $name -or $decoded.artifact_key -ne $Expected[$name].Key -or $decoded.artifact_sha256 -ne $Expected[$name].Digest -or
                $instance.ImageId -ne $ami -or $instanceTags.Fleet -ne $fleetKey -or $instanceTags.Replica -ne '1' -or
                $instanceTags.Role -ne $roleName -or $instanceTags.Region -ne $region -or $instanceTags.ArtifactName -ne $name -or
                $instanceTags.ArtifactKey -ne $Expected[$name].Key -or $instanceTags.ArtifactDigest -ne $Expected[$name].Digest -or
                $instanceTags.ReleaseVersion -ne $Version -or $instanceTags.RunId -ne $runId -or $instanceTags.Lab -ne 'challenge-40' -or $instanceTags.ManagedBy -ne 'terraform' -or
                $templateTags.RunId -ne $runId -or $templateTags.Role -ne $roleName -or $templateTags.Lab -ne 'challenge-40' -or $templateTags.ManagedBy -ne 'terraform' -or
                $sgTags.RunId -ne $runId -or $sgTags.Role -ne $roleName -or $sgTags.Lab -ne 'challenge-40' -or $sgTags.ManagedBy -ne 'terraform') {
                throw "Remote runtime contract, LT user data/tags, SG tags, placement, or EC2 tags are wrong for $replicaKey at $Version."
            }
        }
    }
    Assert-RemoteRuntime '2026.07.1' $expectedV1 $v1Ids

    $reorder = (& terraform "-chdir=$runtime" plan -detailed-exitcode -input=false -no-color @common '-var=runtime_catalog_path=../../fixtures/runtime-reordered.json' 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Runtime catalog reorder changed identity: $reorder" }

    $artifactV2 = 'artifact-v2.tfplan'
    $output = (& terraform "-chdir=$artifact" plan -input=false -no-color "-out=$artifactV2" @common '-var=manifest_path=../../fixtures/manifest-v2.json' 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Artifact v2 plan failed: $output" }
    $artifactUpgrade = @{
        'terraform_data.manifest_guard'     = 'update'
        'aws_s3_object.artifact["api"]'    = 'update'
        'aws_s3_object.artifact["worker"]' = 'update'
    }
    $null = Assert-ExactPlanChanges $artifact $artifactV2 $artifactUpgrade 'artifact v2 promotion'
    $output = (& terraform "-chdir=$artifact" apply -input=false -no-color -auto-approve $artifactV2 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Artifact v2 saved-plan apply failed: $output" }

    $runtimeV2 = 'runtime-v2.tfplan'
    $output = (& terraform "-chdir=$runtime" plan -input=false -no-color "-out=$runtimeV2" @common 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Runtime v2 plan failed: $output" }
    $runtimeUpgrade = @{
        'terraform_data.contract_guard'                                    = 'update'
        'module.primary.aws_launch_template.fleet["api@primary"]'          = 'update'
        'module.dr.aws_launch_template.fleet["worker@dr"]'                 = 'update'
        'module.primary.terraform_data.release_revision["api@primary#01"]' = 'delete,create'
        'module.dr.terraform_data.release_revision["worker@dr#01"]'        = 'delete,create'
        'module.primary.aws_instance.replica["api@primary#01"]'            = 'delete,create'
        'module.dr.aws_instance.replica["worker@dr#01"]'                   = 'delete,create'
    }
    $null = Assert-ExactPlanChanges $runtime $runtimeV2 $runtimeUpgrade 'runtime v2 promotion'
    $output = (& terraform "-chdir=$runtime" apply -input=false -no-color -auto-approve $runtimeV2 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Runtime v2 saved-plan apply failed: $output" }

    $replicaRaw = (& terraform "-chdir=$runtime" output -json replica_ids 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Could not read v2 replica IDs: $replicaRaw" }
    $v2Ids = $replicaRaw | ConvertFrom-Json -AsHashtable
    foreach ($key in @('api@primary#01', 'worker@dr#01')) { if ($v2Ids[$key] -eq $v1Ids[$key]) { throw "$key was not replaced during release promotion." } }
    $expectedV2 = @{
        api    = @{ Digest = 'afb492a1409a48f8d0204e7f0cb6805e81b740c65b9f08e41bd189c42a501b7c'; Body = 'api release 2'; Key = 'releases/api/current.txt' }
        worker = @{ Digest = '729c85cafb2895afd42865e5c1b019123effe7bdb8780a5a63db571490c6d83b'; Body = 'worker release 2'; Key = 'releases/worker/current.txt' }
    }
    foreach ($name in @('api', 'worker')) {
        $bodyPath = Join-Path $temp "$name-v2.txt"
        $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'get-object', '--bucket', $bucket, '--key', $expectedV2[$name].Key, $bodyPath)
        if ((Get-Content -Raw $bodyPath).Trim() -ne $expectedV2[$name].Body) { throw "S3 $name v2 payload is wrong." }
        $tagResult = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'get-object-tagging', '--bucket', $bucket, '--key', $expectedV2[$name].Key)
        $tags = Convert-TagsToMap $tagResult.TagSet
        if ($tags.ArtifactName -ne $name -or $tags.ArtifactDigest -ne $expectedV2[$name].Digest -or $tags.ReleaseVersion -ne '2026.07.2' -or $tags.RunId -ne $runId) { throw "S3 $name v2 tags are wrong." }
    }
    Assert-RemoteRuntime '2026.07.2' $expectedV2 $v2Ids

    $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'ec2', 'create-tags', '--resources', $v2Ids['api@primary#01'], '--tags', "Key=Name,Value=$runId-intentional-drift")
    $driftPlan = 'runtime-drift.tfplan'
    $output = (& terraform "-chdir=$runtime" plan -input=false -no-color "-out=$driftPlan" @common 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Drift recovery plan failed: $output" }
    $driftExpected = @{ 'module.primary.aws_instance.replica["api@primary#01"]' = 'update' }
    $null = Assert-ExactPlanChanges $runtime $driftPlan $driftExpected 'runtime drift recovery'
    $output = (& terraform "-chdir=$runtime" apply -input=false -no-color -auto-approve $driftPlan 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw "Saved drift recovery apply failed: $output" }

    $runtimeClean = (& terraform "-chdir=$runtime" plan -detailed-exitcode -input=false -no-color @common 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Runtime final plan is not clean: $runtimeClean" }
    $artifactClean = (& terraform "-chdir=$artifact" plan -detailed-exitcode -input=false -no-color @common '-var=manifest_path=../../fixtures/manifest-v2.json' 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Artifact final plan is not clean: $artifactClean" }
} catch {
    $failure = $_
} finally {
    $cleanupErrors = [Collections.Generic.List[string]]::new()
    if ($created) {
        $common = @("-var=run_id=$runId", "-var=localstack_endpoint=$LocalstackEndpoint")
        if ((Test-Path $runtime) -and (Test-Path (Join-Path $runtime 'terraform.tfstate'))) {
            Invoke-CleanupStep $cleanupErrors 'Terraform runtime destroy' {
                $destroy = (& terraform "-chdir=$runtime" destroy -auto-approve -input=false -no-color @common 2>&1) -join "`n"
                if ($LASTEXITCODE) { throw $destroy }
            }
        }
        if ((Test-Path $artifact) -and (Test-Path (Join-Path $artifact 'terraform.tfstate'))) {
            Invoke-CleanupStep $cleanupErrors 'Terraform artifact destroy' {
                $destroy = (& terraform "-chdir=$artifact" destroy -auto-approve -input=false -no-color @common '-var=manifest_path=../../fixtures/manifest-v2.json' 2>&1) -join "`n"
                if ($LASTEXITCODE) { throw $destroy }
            }
        }

        # Terraform destroy is the primary path. The following RunId-scoped
        # cleanup is an idempotent safety net and continues after every error.
        $env:AWS_ACCESS_KEY_ID = 'test'
        $env:AWS_SECRET_ACCESS_KEY = 'test'
        $env:AWS_DEFAULT_REGION = 'us-east-1'

        foreach ($region in @('us-east-1', 'us-west-2')) {
            $instanceResult = Invoke-CleanupQuery $cleanupErrors "List $region EC2 instances" {
                Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down')
            }
            $instanceIds = @($instanceResult.Reservations | ForEach-Object { $_.Instances } | Where-Object { $_ } | ForEach-Object { $_.InstanceId })
            foreach ($instanceId in $instanceIds) {
                Invoke-CleanupStep $cleanupErrors "Terminate $region instance $instanceId" {
                    $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'terminate-instances', '--instance-ids', $instanceId)
                }
            }
        }

        foreach ($region in @('us-east-1', 'us-west-2')) {
            $templateResult = Invoke-CleanupQuery $cleanupErrors "List $region launch templates" {
                Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'describe-launch-templates')
            }
            $templates = @($templateResult.LaunchTemplates | Where-Object {
                    $_ -and ($_.LaunchTemplateName -like "$runId-*" -or @(($_.Tags) | Where-Object { $_.Key -eq 'RunId' -and $_.Value -eq $runId }).Count)
                })
            foreach ($template in $templates) {
                Invoke-CleanupStep $cleanupErrors "Delete $region launch template $($template.LaunchTemplateId)" {
                    $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'delete-launch-template', '--launch-template-id', $template.LaunchTemplateId)
                }
            }

            $groupResult = Invoke-CleanupQuery $cleanupErrors "List $region security groups" {
                Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId")
            }
            foreach ($group in @($groupResult.SecurityGroups | Where-Object { $_ })) {
                Invoke-CleanupStep $cleanupErrors "Delete $region security group $($group.GroupId)" {
                    $lastError = $null
                    for ($attempt = 1; $attempt -le 5; $attempt++) {
                        try {
                            $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'delete-security-group', '--group-id', $group.GroupId)
                            $lastError = $null
                            break
                        } catch {
                            $lastError = $_
                            if ($attempt -lt 5) { Start-Sleep -Seconds 1 }
                        }
                    }
                    if ($lastError) { throw $lastError }
                }
            }
        }

        $profilesResult = Invoke-CleanupQuery $cleanupErrors 'List IAM instance profiles' {
            Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'list-instance-profiles')
        }
        foreach ($profile in @($profilesResult.InstanceProfiles | Where-Object { $_.InstanceProfileName -eq "$runId-runtime-profile" })) {
            foreach ($role in @($profile.Roles)) {
                Invoke-CleanupStep $cleanupErrors "Remove role $($role.RoleName) from instance profile" {
                    $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'remove-role-from-instance-profile', '--instance-profile-name', $profile.InstanceProfileName, '--role-name', $role.RoleName)
                }
            }
            Invoke-CleanupStep $cleanupErrors "Delete IAM instance profile $($profile.InstanceProfileName)" {
                $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'delete-instance-profile', '--instance-profile-name', $profile.InstanceProfileName)
            }
        }

        $rolesResult = Invoke-CleanupQuery $cleanupErrors 'List IAM roles' {
            Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'list-roles')
        }
        foreach ($role in @($rolesResult.Roles | Where-Object { $_.RoleName -eq "$runId-runtime-role" })) {
            $attached = Invoke-CleanupQuery $cleanupErrors "List policies attached to $($role.RoleName)" {
                Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'list-attached-role-policies', '--role-name', $role.RoleName)
            }
            foreach ($policy in @($attached.AttachedPolicies)) {
                Invoke-CleanupStep $cleanupErrors "Detach $($policy.PolicyArn) from $($role.RoleName)" {
                    $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'detach-role-policy', '--role-name', $role.RoleName, '--policy-arn', $policy.PolicyArn)
                }
            }
            $inline = Invoke-CleanupQuery $cleanupErrors "List inline policies on $($role.RoleName)" {
                Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'list-role-policies', '--role-name', $role.RoleName)
            }
            foreach ($policyName in @($inline.PolicyNames)) {
                Invoke-CleanupStep $cleanupErrors "Delete inline policy $policyName from $($role.RoleName)" {
                    $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'delete-role-policy', '--role-name', $role.RoleName, '--policy-name', $policyName)
                }
            }
            Invoke-CleanupStep $cleanupErrors "Delete IAM role $($role.RoleName)" {
                $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'delete-role', '--role-name', $role.RoleName)
            }
        }

        $bucketName = "$runId-release-artifacts"
        $bucketsResult = Invoke-CleanupQuery $cleanupErrors 'List S3 buckets for fallback cleanup' {
            Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'list-buckets')
        }
        if (@($bucketsResult.Buckets | Where-Object { $_.Name -eq $bucketName }).Count -eq 1) {
            $versions = Invoke-CleanupQuery $cleanupErrors "List versions in $bucketName" {
                Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'list-object-versions', '--bucket', $bucketName)
            }
            foreach ($entry in @($versions.Versions) + @($versions.DeleteMarkers)) {
                if ($entry -and $entry.Key -and $entry.VersionId) {
                    Invoke-CleanupStep $cleanupErrors "Delete version $($entry.Key)@$($entry.VersionId)" {
                        $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'delete-object', '--bucket', $bucketName, '--key', $entry.Key, '--version-id', $entry.VersionId)
                    }
                }
            }
            $objects = Invoke-CleanupQuery $cleanupErrors "List current objects in $bucketName" {
                Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'list-objects-v2', '--bucket', $bucketName)
            }
            foreach ($object in @($objects.Contents)) {
                Invoke-CleanupStep $cleanupErrors "Delete object $($object.Key)" {
                    $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'delete-object', '--bucket', $bucketName, '--key', $object.Key)
                }
            }
            Invoke-CleanupStep $cleanupErrors "Delete S3 bucket $bucketName" {
                $null = Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'delete-bucket', '--bucket', $bucketName)
            }
        }

        # Verification always runs, even when the primary test or any cleanup
        # step already failed. Query failures are also retained as cleanup errors.
        foreach ($region in @('us-east-1', 'us-west-2')) {
            $instances = Invoke-CleanupQuery $cleanupErrors "Verify $region instances are zero" {
                Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'describe-instances', '--filters', "Name=tag:RunId,Values=$runId", 'Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down')
            }
            $active = @($instances.Reservations | ForEach-Object { $_.Instances } | Where-Object { $_ })
            if ($active.Count) { [void]$cleanupErrors.Add("Residual $region instances: $($active.InstanceId -join ', ')") }
            $templates = Invoke-CleanupQuery $cleanupErrors "Verify $region launch templates are zero" {
                Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'describe-launch-templates')
            }
            $matchingTemplates = @($templates.LaunchTemplates | Where-Object { $_ -and ($_.LaunchTemplateName -like "$runId-*" -or @(($_.Tags) | Where-Object { $_.Key -eq 'RunId' -and $_.Value -eq $runId }).Count) })
            if ($matchingTemplates.Count) { [void]$cleanupErrors.Add("Residual $region launch templates: $($matchingTemplates.LaunchTemplateId -join ', ')") }
            $groups = Invoke-CleanupQuery $cleanupErrors "Verify $region security groups are zero" {
                Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', $region, 'ec2', 'describe-security-groups', '--filters', "Name=tag:RunId,Values=$runId")
            }
            if (@($groups.SecurityGroups).Count) { [void]$cleanupErrors.Add("Residual $region security groups: $($groups.SecurityGroups.GroupId -join ', ')") }
        }

        $verifyBuckets = Invoke-CleanupQuery $cleanupErrors 'Verify S3 bucket is zero' {
            Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 's3api', 'list-buckets')
        }
        if (@($verifyBuckets.Buckets | Where-Object { $_.Name -eq $bucketName }).Count) { [void]$cleanupErrors.Add("Residual S3 bucket: $bucketName") }
        $verifyRoles = Invoke-CleanupQuery $cleanupErrors 'Verify IAM role is zero' {
            Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'list-roles')
        }
        if (@($verifyRoles.Roles | Where-Object { $_.RoleName -eq "$runId-runtime-role" }).Count) { [void]$cleanupErrors.Add("Residual IAM role: $runId-runtime-role") }
        $verifyProfiles = Invoke-CleanupQuery $cleanupErrors 'Verify IAM instance profile is zero' {
            Invoke-AwsJson @('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1', 'iam', 'list-instance-profiles')
        }
        if (@($verifyProfiles.InstanceProfiles | Where-Object { $_.InstanceProfileName -eq "$runId-runtime-profile" }).Count) { [void]$cleanupErrors.Add("Residual IAM instance profile: $runId-runtime-profile") }
    }

    $env:AWS_ACCESS_KEY_ID = $oldAccess
    $env:AWS_SECRET_ACCESS_KEY = $oldSecret
    $env:AWS_DEFAULT_REGION = $oldRegion
    $resolved = [IO.Path]::GetFullPath($temp)
    $safeBase = [IO.Path]::GetFullPath($tempBase)
    if ($resolved.StartsWith($safeBase, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf).StartsWith('tfpro-c40-')) {
        if (Test-Path -LiteralPath $resolved) {
            Invoke-CleanupStep $cleanupErrors "Remove isolated grader directory $resolved" {
                Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
            }
        }
    } elseif (Test-Path -LiteralPath $temp) {
        [void]$cleanupErrors.Add("Refusing to remove unsafe grader path: $temp")
    }
    if (Test-Path -LiteralPath $temp) {
        [void]$cleanupErrors.Add("Isolated grader directory still exists after cleanup: $temp")
    }
    if ($cleanupErrors.Count) {
        $cleanupSummary = ($cleanupErrors | ForEach-Object { " - $_" }) -join "`n"
        if ($failure) {
            $failure = "$failure`nCleanup failures ($($cleanupErrors.Count)):`n$cleanupSummary"
        } else {
            $failure = "Cleanup failures ($($cleanupErrors.Count)):`n$cleanupSummary"
        }
    }
}

if ($failure) { throw $failure }
Write-Host 'PASS: Challenge 40 manifest contracts, plan gates, dual-region promotion, drift recovery, and LocalStack E2E verified.'
