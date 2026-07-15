[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "..\starter"),
  [string]$LocalstackEndpoint = "http://localhost:4566",
  [switch]$UnitOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-LoopbackEndpoint([string]$Endpoint) {
  if ([string]::IsNullOrEmpty($Endpoint) -or $Endpoint.IndexOf([char]13) -ge 0 -or $Endpoint.IndexOf([char]10) -ge 0) {
    throw "LocalstackEndpoint must not contain CR or LF."
  }
  $uri = $null
  $match = [regex]::Match($Endpoint, '\Ahttps?://(?:localhost|127\.0\.0\.1|\[::1\]):(?<port>[1-9][0-9]{0,4})\z', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
  if (-not $match.Success -or [int]$match.Groups['port'].Value -gt 65535 -or
    -not [Uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref]$uri) -or
    $uri.DnsSafeHost -notin @('localhost', '127.0.0.1', '::1') -or $uri.PathAndQuery -ne '/' -or
    -not [string]::IsNullOrEmpty($uri.UserInfo) -or $uri.Port -ne [int]$match.Groups['port'].Value) {
    throw "LocalstackEndpoint must be an HTTP(S) loopback root origin with an explicit port from 1 to 65535."
  }
}

function Remove-HclComments([string]$Text) {
  $builder = [Text.StringBuilder]::new($Text.Length)
  $state = 'code'
  for ($i = 0; $i -lt $Text.Length; $i++) {
    $current = $Text[$i]
    $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
    if ($state -eq 'code') {
      if ($current -eq '"') { [void]$builder.Append($current); $state = 'string' }
      elseif ($current -eq '#') { [void]$builder.Append(' '); $state = 'line' }
      elseif ($current -eq '/' -and $next -eq '/') { [void]$builder.Append('  '); $i++; $state = 'line' }
      elseif ($current -eq '/' -and $next -eq '*') { [void]$builder.Append('  '); $i++; $state = 'block' }
      else { [void]$builder.Append($current) }
    }
    elseif ($state -eq 'string') {
      [void]$builder.Append($current)
      if ($current -eq '\' -and $i + 1 -lt $Text.Length) { $i++; [void]$builder.Append($Text[$i]) }
      elseif ($current -eq '"') { $state = 'code' }
    }
    elseif ($state -eq 'line') {
      if ($current -eq "`n") { [void]$builder.Append($current); $state = 'code' } else { [void]$builder.Append(' ') }
    }
    else {
      if ($current -eq '*' -and $next -eq '/') { [void]$builder.Append('  '); $i++; $state = 'code' }
      elseif ($current -eq "`n") { [void]$builder.Append($current) } else { [void]$builder.Append(' ') }
    }
  }
  return $builder.ToString()
}

function Assert-SameSet([string[]]$Actual, [string[]]$Expected, [string]$Context) {
  $left = @($Actual | Sort-Object)
  $right = @($Expected | Sort-Object)
  if (($left -join "`n") -ne ($right -join "`n")) {
    throw "$Context mismatch. Expected=[$($right -join ', ')] Actual=[$($left -join ', ')]"
  }
}

function Assert-CandidateContract([string]$Root) {
  $tfFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Where-Object { $_.Name -match '(?i)\.tf(?:\.json)?$' })
  if ($tfFiles.Count -lt 4) { throw "Candidate must contain Terraform HCL files." }
  foreach ($file in $tfFiles) {
    if ($file.Name -match '(?i)\.tf\.json$') { throw "JSON HCL is not allowed: $($file.FullName)" }
    if ($file.DirectoryName -ne $Root) { throw "Terraform HCL is only allowed at Candidate root: $($file.FullName)" }
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse HCL files are not allowed." }
  }
  if (@(Get-ChildItem -LiteralPath $Root -Recurse -Force -File -Filter '*.ps1').Count -ne 0) {
    throw "Candidate scripts are out of scope; submit Terraform HCL only."
  }

  $source = ($tfFiles | Sort-Object FullName | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
  if ($source -match '(?i)\bTODO\b|CHANGEME|__[^\s"]*PLACEHOLDER') {
    throw "Candidate still contains an unfinished marker."
  }
  $safe = Remove-HclComments $source

  if ([regex]::Matches($safe, '(?m)^\s*required_version\s*=\s*"~>\s*1\.6"\s*$').Count -ne 1 -or
    [regex]::Matches($safe, '(?m)^\s*version\s*=\s*"~>\s*5\.100\.0"\s*$').Count -ne 1) {
    throw "Terraform and AWS provider constraints must remain ~> 1.6 and ~> 5.100.0."
  }

  $providers = @([regex]::Matches($safe, '(?m)^\s*provider\s+"aws"\s*\{'))
  if ($providers.Count -ne 1) { throw "Exactly one AWS provider block is required." }
  $requiredProviderLines = @(
    'region\s*=\s*var\.aws_region',
    'access_key\s*=\s*"test"',
    'secret_key\s*=\s*"test"',
    'skip_credentials_validation\s*=\s*true',
    'skip_metadata_api_check\s*=\s*true',
    'skip_requesting_account_id\s*=\s*true',
    's3_use_path_style\s*=\s*true',
    's3\s*=\s*var\.localstack_endpoint',
    'sts\s*=\s*var\.localstack_endpoint'
  )
  foreach ($pattern in $requiredProviderLines) {
    if ([regex]::Matches($safe, "(?m)^\s*$pattern\s*$").Count -ne 1) { throw "AWS provider contract is incomplete: $pattern" }
  }
  if ($safe -notmatch '\\\\z' -or $safe -match '(?im)^\s*(?:profile|token|shared_config_files|shared_credentials_files)\s*=|AKIA[0-9A-Z]{16}|\bbackend\s+"') {
    throw "Loopback validation, credential isolation, or local state contract was violated."
  }

  $resourceMatches = @([regex]::Matches($safe, '(?m)^\s*resource\s+"([^"]+)"\s+"([^"]+)"\s*\{'))
  $resources = @($resourceMatches | ForEach-Object { "$($_.Groups[1].Value).$($_.Groups[2].Value)" })
  Assert-SameSet $resources @('aws_s3_bucket.release', 'aws_s3_object.artifact') 'Managed resource blocks'

  $dataMatches = @([regex]::Matches($safe, '(?m)^\s*data\s+"([^"]+)"\s+"([^"]+)"\s*\{'))
  foreach ($match in $dataMatches) {
    if ($match.Groups[1].Value -ne 'aws_caller_identity') { throw "Only optional data.aws_caller_identity is allowed." }
  }

  $checks = @([regex]::Matches($safe, '(?m)^\s*check\s+"([^"]+)"\s*\{') | ForEach-Object { $_.Groups[1].Value })
  Assert-SameSet $checks @('manifest_header', 'manifest_not_empty', 'artifact_names_unique', 'artifact_fields_valid', 'object_keys_unique', 'enabled_artifacts_present') 'Check blocks'

  $outputs = @([regex]::Matches($safe, '(?m)^\s*output\s+"([^"]+)"\s*\{') | ForEach-Object { $_.Groups[1].Value })
  Assert-SameSet $outputs @('artifact_names', 'bucket_name', 'object_keys', 'managed_addresses', 'release_contract') 'Outputs'

  $requiredConstructs = @(
    'jsondecode(file(var.manifest_path))',
    '=> artifact...',
    'for_each = local.enabled_artifacts',
    'force_destroy = true',
    'etag         = md5(each.value.content)',
    'sha256(jsonencode(local.canonical_manifest))',
    'bucket       = aws_s3_bucket.release.id',
    'lifecycle {'
  )
  foreach ($needle in $requiredConstructs) {
    if (-not $safe.Contains($needle)) { throw "Required Terraform construct is missing: $needle" }
  }
  foreach ($needle in @('content_type', 'metadata', 'tags', 'ManifestSha256')) {
    if ($safe -notmatch "\b$needle\b") { throw "Required release attribute is missing: $needle" }
  }
  return $tfFiles
}

function Invoke-Terraform([string[]]$Arguments, [string]$Context) {
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = @(& terraform @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }
  $output | ForEach-Object { Write-Host $_ }
  if ($exitCode -ne 0) { throw "$Context failed with exit code $exitCode." }
  return ,$output
}

function Invoke-TerraformDetailed([string[]]$Arguments) {
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = @(& terraform @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }
  return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Read-PlanJson([string]$PlanPath) {
  $result = Invoke-TerraformDetailed @('show', '-json', $PlanPath)
  $raw = @($result.Output)
  if ($result.ExitCode -ne 0) { throw "terraform show -json failed for $PlanPath." }
  return (($raw -join "`n") | ConvertFrom-Json)
}

function Get-ChangedResources([object]$Plan) {
  return @($Plan.resource_changes | Where-Object { (@($_.change.actions) -join ',') -ne 'no-op' })
}

function Assert-PlanChanges([object]$Plan, [string[]]$ExpectedAddresses, [string]$ExpectedAction, [string]$Context) {
  $changed = @(Get-ChangedResources $Plan)
  Assert-SameSet @($changed | ForEach-Object { $_.address }) $ExpectedAddresses $Context
  foreach ($change in $changed) {
    $actions = @($change.change.actions) -join ','
    if ($actions -ne $ExpectedAction) { throw "$Context has unexpected actions at $($change.address): $actions" }
    if ($change.type -notin @('aws_s3_bucket', 'aws_s3_object')) { throw "$Context contains a forbidden type: $($change.type)" }
  }
}

function Get-S3ObjectText([string]$Endpoint, [string]$Bucket, [string]$Key) {
  $uri = "$($Endpoint.TrimEnd('/'))/$Bucket/$Key"
  $response = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing
  if ($response.Content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($response.Content) }
  return [string]$response.Content
}

function Get-HttpStatus([string]$Uri) {
  try {
    $response = Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing
    return [int]$response.StatusCode
  }
  catch {
    if ($null -ne $_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
    throw
  }
}

Assert-LoopbackEndpoint $LocalstackEndpoint
if ($null -eq (Get-Command terraform -ErrorAction SilentlyContinue)) { throw "terraform is required." }

$originalLocation = (Get-Location).Path
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$candidateRoot = (Resolve-Path -LiteralPath $Candidate).Path
$scratchRoot = Join-Path ([IO.Path]::GetTempPath()) ("tfpro-c27-" + [guid]::NewGuid().ToString('N'))
$workRoot = Join-Path $scratchRoot 'candidate'
$fixtureRoot = Join-Path $scratchRoot 'fixtures'
$prefix = 'c27-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$bucket = "$prefix-dev-artifacts"
$canonicalManifest = Join-Path $fixtureRoot 'release-v1.json'
$reorderedManifest = Join-Path $fixtureRoot 'release-v1-reordered.json'
$baseVariables = @("-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=manifest_path=$canonicalManifest")
$expectedAddresses = @(
  'aws_s3_bucket.release',
  'aws_s3_object.artifact["api-config"]',
  'aws_s3_object.artifact["release-notes"]',
  'aws_s3_object.artifact["worker-config"]'
)
$testPassed = $false
$e2eStarted = $false

try {
  New-Item -ItemType Directory -Path $workRoot, $fixtureRoot, (Join-Path $workRoot 'tests') -Force | Out-Null
  Get-ChildItem -LiteralPath $candidateRoot -Force | Copy-Item -Destination $workRoot -Recurse -Force
  Get-ChildItem -LiteralPath (Join-Path $labRoot 'fixtures') -Force | Copy-Item -Destination $fixtureRoot -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'pipeline.tftest.hcl') -Destination (Join-Path $workRoot 'tests\pipeline.tftest.hcl') -Force

  [void](Assert-CandidateContract $workRoot)
  Set-Location $workRoot
  Invoke-Terraform @('fmt', '-check', '-recursive') 'terraform fmt' | Out-Null
  Invoke-Terraform @('init', '-input=false', '-no-color') 'terraform init' | Out-Null
  Invoke-Terraform @('validate', '-no-color') 'terraform validate' | Out-Null

  $testResult = Invoke-TerraformDetailed @('test', '-no-color')
  $testOutput = @($testResult.Output)
  $testExit = $testResult.ExitCode
  $testOutput | ForEach-Object { Write-Host $_ }
  $testText = $testOutput -join "`n"
  if ($testExit -ne 0) { throw "Canonical tests failed with exit code $testExit." }
  if ([regex]::Matches($testText, '(?m)^Success! 9 passed, 0 failed\.$').Count -ne 1) {
    throw "Exactly 9 canonical runs must pass."
  }
  $testPassed = $true

  if ($UnitOnly) {
    Write-Host "PASS: Terraform 1.6-compatible canonical suite passed 9/9; E2E skipped."
    return
  }

  if ($null -eq (Get-Command aws -ErrorAction SilentlyContinue)) { throw "AWS CLI is required for E2E drift injection." }
  $health = Get-HttpStatus "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health"
  if ($health -ne 200) { throw "LocalStack health endpoint is not ready: HTTP $health" }

  $env:AWS_ACCESS_KEY_ID = 'test'
  $env:AWS_SECRET_ACCESS_KEY = 'test'
  $env:AWS_DEFAULT_REGION = 'us-east-1'
  $env:AWS_EC2_METADATA_DISABLED = 'true'
  $e2eStarted = $true

  Invoke-Terraform (@('plan', '-input=false', '-no-color', '-out=initial.tfplan') + $baseVariables) 'initial saved plan' | Out-Null
  $initialPlan = Read-PlanJson 'initial.tfplan'
  Assert-PlanChanges $initialPlan $expectedAddresses 'create' 'Initial plan'
  Invoke-Terraform @('apply', '-input=false', '-no-color', 'initial.tfplan') 'apply initial saved plan' | Out-Null

  $outputResult = Invoke-TerraformDetailed @('output', '-json')
  $outputRaw = @($outputResult.Output)
  if ($outputResult.ExitCode -ne 0) { throw "terraform output failed." }
  $outputs = (($outputRaw -join "`n") | ConvertFrom-Json)
  if ($outputs.bucket_name.value -ne $bucket) { throw "Unexpected bucket output." }
  Assert-SameSet @($outputs.managed_addresses.value) $expectedAddresses 'Applied managed addresses'

  $expectedContent = [ordered]@{
    'releases/2026.07.1/config/api.json'    = '{"feature":"stable","limit":20}'
    'releases/2026.07.1/docs/release.txt'   = 'orders-api release 2026.07.1'
    'releases/2026.07.1/config/worker.json' = '{"concurrency":4,"queue":"orders"}'
  }
  foreach ($entry in $expectedContent.GetEnumerator()) {
    $actual = Get-S3ObjectText $LocalstackEndpoint $bucket $entry.Key
    if ($actual -ne $entry.Value) { throw "S3 content mismatch for $($entry.Key)." }
  }

  $clean = Invoke-TerraformDetailed (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $baseVariables)
  $clean.Output | ForEach-Object { Write-Host $_ }
  if ($clean.ExitCode -ne 0) { throw "Canonical post-apply plan must be clean, exit=$($clean.ExitCode)." }

  $reorderVariables = @("-var=name_prefix=$prefix", "-var=localstack_endpoint=$LocalstackEndpoint", "-var=manifest_path=$reorderedManifest")
  $reordered = Invoke-TerraformDetailed (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $reorderVariables)
  $reordered.Output | ForEach-Object { Write-Host $_ }
  if ($reordered.ExitCode -ne 0) { throw "Reordered manifest must produce a clean plan, exit=$($reordered.ExitCode)." }

  $driftKey = 'releases/2026.07.1/config/api.json'
  $driftFile = Join-Path $scratchRoot 'drift.json'
  [IO.File]::WriteAllText($driftFile, '{"feature":"tampered","limit":999}', [Text.UTF8Encoding]::new($false))
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $awsOutput = @(& aws --endpoint-url $LocalstackEndpoint s3api put-object --bucket $bucket --key $driftKey --body $driftFile --content-type 'application/json' 2>&1)
    $awsExit = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousPreference
  }
  if ($awsExit -ne 0) { throw "AWS CLI drift injection failed: $($awsOutput -join ' ')" }
  if ((Get-S3ObjectText $LocalstackEndpoint $bucket $driftKey) -notmatch 'tampered') { throw "Drift injection was not observable." }

  Invoke-Terraform (@('plan', '-input=false', '-no-color', '-out=repair.tfplan') + $baseVariables) 'saved repair plan' | Out-Null
  $repairPlan = Read-PlanJson 'repair.tfplan'
  Assert-PlanChanges $repairPlan @('aws_s3_object.artifact["api-config"]') 'update' 'Repair plan'
  Invoke-Terraform @('apply', '-input=false', '-no-color', 'repair.tfplan') 'apply saved repair plan' | Out-Null
  if ((Get-S3ObjectText $LocalstackEndpoint $bucket $driftKey) -ne $expectedContent[$driftKey]) { throw "Repair did not restore declared content." }

  $postRepair = Invoke-TerraformDetailed (@('plan', '-detailed-exitcode', '-input=false', '-no-color') + $baseVariables)
  $postRepair.Output | ForEach-Object { Write-Host $_ }
  if ($postRepair.ExitCode -ne 0) { throw "Post-repair plan must be clean, exit=$($postRepair.ExitCode)." }

  Invoke-Terraform (@('plan', '-destroy', '-input=false', '-no-color', '-out=destroy.tfplan') + $baseVariables) 'saved destroy plan' | Out-Null
  $destroyPlan = Read-PlanJson 'destroy.tfplan'
  Assert-PlanChanges $destroyPlan $expectedAddresses 'delete' 'Destroy plan'
  Invoke-Terraform @('apply', '-input=false', '-no-color', 'destroy.tfplan') 'apply saved destroy plan' | Out-Null

  $status = Get-HttpStatus "$($LocalstackEndpoint.TrimEnd('/'))/$bucket"
  if ($status -ne 404) { throw "Bucket remains after destroy: HTTP $status" }
}
finally {
  try {
    if ($e2eStarted -and (Test-Path -LiteralPath $workRoot)) {
      Set-Location $workRoot
      if (Test-Path -LiteralPath (Join-Path $workRoot 'terraform.tfstate')) {
        $cleanupResult = Invoke-TerraformDetailed (@('destroy', '-auto-approve', '-input=false', '-no-color') + $baseVariables)
        if ($cleanupResult.ExitCode -ne 0) { Write-Warning "Terraform cleanup failed: $($cleanupResult.Output -join ' ')" }
      }
      $remaining = Get-HttpStatus "$($LocalstackEndpoint.TrimEnd('/'))/$bucket"
      if ($remaining -ne 404 -and $null -ne (Get-Command aws -ErrorAction SilentlyContinue)) {
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
          & aws --endpoint-url $LocalstackEndpoint s3 rm "s3://$bucket" --recursive 2>&1 | Out-Null
          & aws --endpoint-url $LocalstackEndpoint s3api delete-bucket --bucket $bucket 2>&1 | Out-Null
        }
        finally { $ErrorActionPreference = $oldPreference }
      }
    }
  }
  finally {
    Set-Location $originalLocation
    if (Test-Path -LiteralPath $scratchRoot) { Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

if (-not $testPassed) { throw "Canonical tests did not complete." }
Write-Host "PASS: 9/9 canonical runs; saved-plan apply, reorder no-op, one-object drift repair, clean plan, audited destroy, and zero residuals verified."
