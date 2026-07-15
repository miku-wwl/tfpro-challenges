[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot '..\starter'),
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Endpoint([string]$Value) {
  if ($Value -notmatch '^https?://(?:localhost|127\.0\.0\.1|\[::1\]):[0-9]{1,5}$') { throw "Unsafe LocalStack endpoint: $Value" }
  try { $uri = [Uri]$Value } catch { throw "Invalid LocalStack endpoint: $Value" }
  if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http','https') -or $uri.DnsSafeHost -notin @('localhost','127.0.0.1','::1') -or
      $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535) {
    throw "Unsafe LocalStack endpoint: $Value"
  }
}

function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $lines = @(& $File @Arguments 2>&1); $code = $LASTEXITCODE
  $ErrorActionPreference = $previous
  $text = $lines -join "`n"
  if ($lines.Count -gt 0) { $lines | Out-Host }
  if ($code -notin $Allowed) { throw "$File $($Arguments -join ' ') failed with exit code $code.`n$text" }
  return [pscustomobject]@{ Code = $code; Text = $text }
}

function Tf([string]$Dir, [string[]]$Arguments, [int[]]$Allowed = @(0)) {
  return Invoke-Native 'terraform' (@("-chdir=$Dir") + $Arguments) $Allowed
}

function Aws([string[]]$Arguments, [int[]]$Allowed = @(0)) {
  return Invoke-Native 'aws.exe' (@('--endpoint-url', $LocalstackEndpoint, '--region', 'us-east-1') + $Arguments) $Allowed
}

function Copy-Clean([string]$Source, [string]$Destination) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    if ($item.Name -in @('.terraform','.terraform.lock.hcl','terraform.tfstate','terraform.tfstate.backup','.terraform.tfstate.lock.info') -or $item.Extension -in @('.tfplan','.tfstate')) { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
  }
}

function Get-Contract([string]$Dir) {
  $r = Tf $Dir @('output','-json','release_contract')
  return $r.Text | ConvertFrom-Json
}

function Assert-Tests([string]$Dir, [int]$Expected) {
  $r = Tf $Dir @('test','-test-directory=tests','-no-color')
  if ([regex]::Matches($r.Text, "(?m)^Success!\s+$Expected passed,\s+0 failed\.\s*$").Count -ne 1 -or
      [regex]::Matches($r.Text, '(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne $Expected) {
    throw "Expected exactly $Expected Terraform test runs."
  }
}

Assert-Endpoint $LocalstackEndpoint

$candidatePath = (Resolve-Path -LiteralPath $Candidate).Path
$files = @(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if ($files.Count -eq 0 -or @($files | Where-Object { $_.Extension -ne '.tf' }).Count -ne 0) { throw 'Candidate must contain Terraform HCL files only.' }
$text = ($files | Where-Object Extension -eq '.tf' | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($text -match '\bterraform\.workspace\b') { throw 'CLI workspaces are not part of this environment-isolation contract.' }
if ([regex]::Matches($text, 'backend\s+"s3"\s*\{\s*\}').Count -ne 1) { throw 'Exactly one empty partial S3 backend is required.' }
if ([regex]::Matches($text, 'resource\s+"aws_s3_bucket"\s+"release"').Count -ne 1 -or
    [regex]::Matches($text, 'resource\s+"aws_s3_object"\s+"release"').Count -ne 1) { throw 'Exact S3 bucket/object release resources are required.' }
if ($text -notmatch 'for_each\s*=\s*local\.active_services' -or $text -notmatch 'csvdecode\s*\(' -or $text -notmatch 'duplicate_services' -or $text -notmatch 'output\s+"catalog_guard"[\s\S]*?precondition' -or
    $text -notmatch 'contains\s*\(\s*\["dev",\s*"stage",\s*"prod"\]') { throw 'Stable catalog and explicit environment guards are incomplete.' }
if ($text -notmatch 'access_key\s*=\s*"test"' -or $text -notmatch 'secret_key\s*=\s*"test"' -or
    $text -notmatch 'skip_credentials_validation\s*=\s*true' -or $text -notmatch 'skip_metadata_api_check\s*=\s*true' -or
    $text -notmatch 'skip_requesting_account_id\s*=\s*true') { throw 'Safe LocalStack provider contract is incomplete.' }
if ($text -match '(?i)\b(mock_provider|override_data|override_resource|profile|shared_credentials_files|assume_role)\b|AKIA[0-9A-Z]{16}') { throw 'Forbidden mock or credential mechanism found.' }
$awsTypes = @([regex]::Matches($text, 'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($awsTypes -join ',') -ne 'aws_s3_bucket,aws_s3_object') { throw "Unexpected AWS managed resource type: $($awsTypes -join ',')" }
if ($text -match 'resource\s+"terraform_data"') { throw 'terraform_data is not part of this managed graph.' }

$runId = ([Guid]::NewGuid().ToString('N')).Substring(0,10)
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c33-$runId"
$testDir = Join-Path $temp 'test'
$stateBucket = "tfpro-c33-state-$runId"
$prefix = 'tfpro-c33'
$oldAccess = $env:AWS_ACCESS_KEY_ID; $oldSecret = $env:AWS_SECRET_ACCESS_KEY; $oldRegion = $env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID = 'test'; $env:AWS_SECRET_ACCESS_KEY = 'test'; $env:AWS_DEFAULT_REGION = 'us-east-1'
$roots = @{}
$failure = $null

try {
  Copy-Clean $candidatePath $testDir
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\fixtures') -Destination (Join-Path $testDir 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force -Path (Join-Path $testDir 'tests') | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $testDir 'tests\canonical.tftest.hcl')
  Tf $testDir @('fmt','-check','-recursive') | Out-Null
  Tf $testDir @('init','-backend=false','-input=false','-no-color') | Out-Null
  Tf $testDir @('validate','-no-color') | Out-Null
  Assert-Tests $testDir 8
  if ($UnitOnly) { Write-Host 'PASS: Challenge 33 exact Terraform 1.6 canonical tests.'; return }

  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null } catch { throw 'LocalStack is unavailable.' }
  Aws @('s3api','create-bucket','--bucket',$stateBucket) | Out-Null

  foreach ($environment in @('dev','stage','prod')) {
    $dir = Join-Path $temp $environment; $roots[$environment] = $dir
    Copy-Clean $candidatePath $dir
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\fixtures') -Destination (Join-Path $dir 'fixtures') -Recurse -Force
    $backend = @('init','-input=false','-no-color',"-backend-config=bucket=$stateBucket","-backend-config=key=environments/$environment.tfstate",'-backend-config=region=us-east-1',"-backend-config=endpoint=$LocalstackEndpoint",'-backend-config=access_key=test','-backend-config=secret_key=test','-backend-config=force_path_style=true','-backend-config=skip_credentials_validation=true','-backend-config=skip_metadata_api_check=true','-backend-config=skip_requesting_account_id=true')
    Tf $dir $backend | Out-Null
  }

  $plans = @{}
  $planHashes = @{}
  foreach ($environment in @('dev','stage','prod')) {
    $dir = $roots[$environment]; $plan = Join-Path $dir "$environment.tfplan"; $plans[$environment] = $plan
    Tf $dir @('plan','-input=false','-no-color',"-out=$plan","-var=environment=$environment","-var=name_prefix=$prefix","-var=run_id=$runId",'-var=catalog_file=fixtures/services.csv') | Out-Null
    $planHashes[$environment] = (Get-FileHash -LiteralPath $plan -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($planHashes[$environment] -notmatch '^[0-9a-f]{64}$') { throw "$environment saved plan SHA256 audit failed." }
    $planJson = (Tf $dir @('show','-json',$plan)).Text | ConvertFrom-Json
    $actions = @($planJson.resource_changes | Where-Object { (@($_.change.actions) -join ',') -ne 'no-op' })
    if ($actions.Count -ne 4 -or @($actions | Where-Object { (@($_.change.actions) -join ',') -ne 'create' }).Count -ne 0) { throw "$environment saved plan must contain exactly four creates and no destructive action." }
    foreach ($service in @('api','worker')) {
      $bucketAddress = "aws_s3_bucket.release[`"$service`"]"
      $objectAddress = "aws_s3_object.release[`"$service`"]"
      $bucketChange = @($actions | Where-Object address -eq $bucketAddress)
      $objectChange = @($actions | Where-Object address -eq $objectAddress)
      if ($bucketChange.Count -ne 1 -or $objectChange.Count -ne 1) { throw "$environment saved plan address contract is incomplete for $service." }
      $expectedBucket = "$prefix-$environment-$service-$runId"
      $bucketAfter = $bucketChange[0].change.after
      $objectAfter = $objectChange[0].change.after
      if ($bucketAfter.bucket -ne $expectedBucket -or $bucketAfter.tags.Environment -ne $environment -or
          $bucketAfter.tags.Service -ne $service -or $bucketAfter.tags.ManagedBy -ne 'terraform') {
        throw "$environment saved plan bucket contract mismatch for $service."
      }
      if ($objectAfter.key -ne "releases/$environment.json" -or $objectAfter.tags.Environment -ne $environment -or
          $objectAfter.tags.Service -ne $service -or $objectAfter.tags.ManagedBy -ne 'terraform' -or
          $objectAfter.metadata.environment -ne $environment -or $objectAfter.metadata.service -ne $service) {
        throw "$environment saved plan object contract mismatch for $service."
      }
    }
  }
  if (@($planHashes.Values | Sort-Object -Unique).Count -ne 3) { throw 'Saved plan audit hashes must be unique per explicit environment contract.' }
  foreach ($environment in @('dev','stage','prod')) {
    Tf $roots[$environment] @('apply','-input=false','-no-color',$plans[$environment]) | Out-Null
  }

  $stateListing = (Aws @('s3api','list-objects-v2','--bucket',$stateBucket,'--prefix','environments/','--output','json')).Text | ConvertFrom-Json
  $stateKeys = @($stateListing.Contents | ForEach-Object Key | Sort-Object)
  $expectedStateKeys = @('environments/dev.tfstate','environments/prod.tfstate','environments/stage.tfstate')
  if (($stateKeys -join "`n") -ne ($expectedStateKeys -join "`n")) { throw "Unexpected S3 backend state keys: $($stateKeys -join ', ')" }

  foreach ($environment in @('dev','stage','prod')) {
    $dir = $roots[$environment]; $contract = Get-Contract $dir
    if ($contract.environment -ne $environment) { throw "$environment output contract mismatch." }
    $stateAddresses = @((Tf $dir @('state','list')).Text -split "`r?`n" | Where-Object { $_ -ne '' } | Sort-Object)
    $expectedAddresses = @('aws_s3_bucket.release["api"]','aws_s3_bucket.release["worker"]','aws_s3_object.release["api"]','aws_s3_object.release["worker"]')
    if (($stateAddresses -join "`n") -ne ($expectedAddresses -join "`n")) { throw "$environment state address contract mismatch." }
    foreach ($service in @('api','worker')) {
      $bucket = "$prefix-$environment-$service-$runId"; $key = "releases/$environment.json"
      if ($contract.buckets.$service -ne $bucket -or $contract.objects.$service -ne $key -or
          $contract.environment_tags.buckets.$service -ne $environment -or $contract.environment_tags.objects.$service -ne $environment) {
        throw "$environment output resource contract mismatch for $service."
      }
      Aws @('s3api','head-bucket','--bucket',$bucket) | Out-Null
      $head = Aws @('s3api','head-object','--bucket',$bucket,'--key',$key,'--output','json')
      $metadata = ($head.Text | ConvertFrom-Json).Metadata
      if ($metadata.environment -ne $environment -or $metadata.service -ne $service) { throw "$bucket/$key metadata mismatch." }
      $tagSet = ((Aws @('s3api','get-object-tagging','--bucket',$bucket,'--key',$key,'--output','json')).Text | ConvertFrom-Json).TagSet
      $tags = @{}; foreach ($tag in $tagSet) { $tags[$tag.Key] = $tag.Value }
      if ($tags.Environment -ne $environment -or $tags.Service -ne $service -or $tags.ManagedBy -ne 'terraform') { throw "$bucket/$key tags mismatch." }
      $body = Join-Path $temp "$environment-$service.json"; Aws @('s3api','get-object','--bucket',$bucket,'--key',$key,$body) | Out-Null
      $payload = Get-Content -Raw -LiteralPath $body | ConvertFrom-Json
      if ($payload.environment -ne $environment -or $payload.service -ne $service) { throw "$bucket/$key payload mismatch." }
    }
  }

  $driftFile = Join-Path $temp 'drift.json'; [IO.File]::WriteAllText($driftFile,'{"drift":true}',[Text.UTF8Encoding]::new($false))
  Aws @('s3api','put-object','--bucket',"$prefix-dev-api-$runId",'--key','releases/dev.json','--body',$driftFile) | Out-Null
  $commonDev = @('-input=false','-no-color','-var=environment=dev',"-var=name_prefix=$prefix","-var=run_id=$runId",'-var=catalog_file=fixtures/services.csv')
  $devDrift = Tf $roots['dev'] (@('plan','-detailed-exitcode') + $commonDev) @(0,2)
  if ($devDrift.Code -ne 2) { throw 'Dev object drift was not detected.' }
  $stageClean = Tf $roots['stage'] @('plan','-detailed-exitcode','-input=false','-no-color','-var=environment=stage',"-var=name_prefix=$prefix","-var=run_id=$runId",'-var=catalog_file=fixtures/services.csv') @(0,2)
  if ($stageClean.Code -ne 0) { throw 'Dev drift leaked into stage state.' }
  $prodClean = Tf $roots['prod'] @('plan','-detailed-exitcode','-input=false','-no-color','-var=environment=prod',"-var=name_prefix=$prefix","-var=run_id=$runId",'-var=catalog_file=fixtures/services.csv') @(0,2)
  if ($prodClean.Code -ne 0) { throw 'Dev drift leaked into prod state.' }
  Tf $roots['dev'] (@('apply','-auto-approve') + $commonDev) | Out-Null
  $reorder = Tf $roots['dev'] @('plan','-detailed-exitcode','-input=false','-no-color','-var=environment=dev',"-var=name_prefix=$prefix","-var=run_id=$runId",'-var=catalog_file=fixtures/services-reordered.csv') @(0,2)
  if ($reorder.Code -ne 0) { throw 'Catalog reorder changed the graph.' }

  foreach ($environment in @('prod','stage','dev')) {
    Tf $roots[$environment] @('destroy','-auto-approve','-input=false','-no-color',"-var=environment=$environment","-var=name_prefix=$prefix","-var=run_id=$runId",'-var=catalog_file=fixtures/services.csv') | Out-Null
  }
  Aws @('s3','rb',"s3://$stateBucket",'--force') | Out-Null
  $remaining = Aws @('s3api','list-buckets','--query','Buckets[].Name','--output','text')
  if ($remaining.Text -match "$prefix-(dev|stage|prod)-") { throw 'Challenge 33 S3 residue remains.' }
  Write-Host 'PASS: Challenge 33 TF1.6 tests + audited environment-bound saved plans + exact S3 state keys + real S3 drift/reorder + zero residue.'
}
catch { $failure = $_ }
finally {
  $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  foreach ($environment in @('prod','stage','dev')) {
    if ($roots.ContainsKey($environment) -and (Test-Path $roots[$environment])) {
      & terraform "-chdir=$($roots[$environment])" destroy -auto-approve -input=false -no-color "-var=environment=$environment" "-var=name_prefix=$prefix" "-var=run_id=$runId" '-var=catalog_file=fixtures/services.csv' 2>$null | Out-Null
    }
  }
  & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 s3 rb "s3://$stateBucket" --force 2>$null | Out-Null
  $env:AWS_ACCESS_KEY_ID = $oldAccess; $env:AWS_SECRET_ACCESS_KEY = $oldSecret; $env:AWS_DEFAULT_REGION = $oldRegion
  if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
  $ErrorActionPreference = $previous
}
if ($failure) { throw $failure }
