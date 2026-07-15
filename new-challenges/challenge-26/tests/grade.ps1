[CmdletBinding()]
param(
  [string]$Candidate = (Join-Path $PSScriptRoot "..\starter"),
  [string]$LocalstackEndpoint = "http://localhost:4566",
  [switch]$UnitOnly
)

$ErrorActionPreference = "Stop"
function Assert-LoopbackEndpoint {
  param([string]$Endpoint)
  $uri = $null
  if (-not [uri]::TryCreate($Endpoint, [System.UriKind]::Absolute, [ref]$uri)) {
    throw "LocalstackEndpoint  URI"
  }
  $endpointHost = $uri.Host.Trim('[', ']').ToLowerInvariant()
  if ($uri.Scheme -notin @("http", "https") -or
    $endpointHost -notin @("localhost", "127.0.0.1", "::1") -or
    -not [string]::IsNullOrEmpty($uri.UserInfo) -or $uri.IsDefaultPort -or
    $uri.AbsolutePath -ne "/" -or
    -not [string]::IsNullOrEmpty($uri.Query) -or
    -not [string]::IsNullOrEmpty($uri.Fragment)) {
    throw "LocalstackEndpoint  localhost127.0.0.1  ::1  HTTP(S) "
  }
}

Assert-LoopbackEndpoint $LocalstackEndpoint

$originalLocation = (Get-Location).Path
$labRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$candidateRoot = (Resolve-Path $Candidate).Path
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tfpro-c26-" + [guid]::NewGuid().ToString("N"))
$workRoot = Join-Path $scratchRoot "candidate"
$uniquePrefix = "c26-" + [guid]::NewGuid().ToString("N").Substring(0, 10)

function Remove-HclComments {
  param([string]$Text)
  $builder = [System.Text.StringBuilder]::new()
  $inString = $false
  $inLineComment = $false
  $inBlockComment = $false
  $escaped = $false
  for ($index = 0; $index -lt $Text.Length; $index++) {
    $character = $Text[$index]
    $next = if ($index + 1 -lt $Text.Length) { $Text[$index + 1] } else { [char]0 }
    if ($inLineComment) {
      if ($character -eq "`n" -or $character -eq "`r") {
        $inLineComment = $false
        [void]$builder.Append($character)
      }
      continue
    }
    if ($inBlockComment) {
      if ($character -eq '*' -and $next -eq '/') {
        $inBlockComment = $false
        $index++
      }
      elseif ($character -eq "`n" -or $character -eq "`r") {
        [void]$builder.Append($character)
      }
      continue
    }
    if ($inString) {
      [void]$builder.Append($character)
      if ($escaped) { $escaped = $false }
      elseif ($character -eq [char]92) { $escaped = $true }
      elseif ($character -eq '"') { $inString = $false }
      continue
    }
    if ($character -eq '"') {
      $inString = $true
      [void]$builder.Append($character)
    }
    elseif ($character -eq '#') { $inLineComment = $true }
    elseif ($character -eq '/' -and $next -eq '/') {
      $inLineComment = $true
      $index++
    }
    elseif ($character -eq '/' -and $next -eq '*') {
      $inBlockComment = $true
      $index++
    }
    else { [void]$builder.Append($character) }
  }
  return $builder.ToString()
}

function Assert-AwsProviderContract {
  param([string]$Source)
  $cleanSource = Remove-HclComments $Source
  $blocks = @([regex]::Matches($cleanSource, '(?ms)^provider\s+"aws"\s*\{.*?^\}'))
  if ($blocks.Count -ne 1) { throw " AWS provider block" }
  $block = $blocks[0].Value
  $requiredAssignments = @{
    access_key                  = '"test"'
    secret_key                  = '"test"'
    region                      = 'var\.aws_region'
    skip_credentials_validation = 'true'
    skip_metadata_api_check     = 'true'
    skip_requesting_account_id  = 'true'
    iam                         = 'var\.localstack_endpoint'
    sts                         = 'var\.localstack_endpoint'
  }
  foreach ($name in $requiredAssignments.Keys) {
    $pattern = '(?m)^\s*' + [regex]::Escape($name) + '\s*=\s*' + $requiredAssignments[$name] + '\s*$'
    if ([regex]::Matches($block, $pattern).Count -ne 1) {
      throw "AWS provider  $name test/testendpoint  localstack_endpoint"
    }
  }
}

function Invoke-Terraform {
  param([string[]]$Arguments)
  & terraform @Arguments
  if ($LASTEXITCODE -ne 0) { throw "terraform $($Arguments -join ' ') exit code=$LASTEXITCODE" }
}

function Get-PlanChanges {
  param([string]$PlanPath)
  $raw = (& terraform show -json $PlanPath) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "terraform show -json failed for $PlanPath" }
  $plan = $raw | ConvertFrom-Json
  return @($plan.resource_changes | Where-Object { (@($_.change.actions) -join ',') -ne 'no-op' })
}

function Get-LocalStackIamXml {
  param([string]$Action, [string]$ExtraQuery = "")
  $uri = "$LocalstackEndpoint/?Action=$Action&Version=2010-05-08$ExtraQuery"
  $response = Invoke-WebRequest -Uri $uri -UseBasicParsing
  if ($response.Content -is [byte[]]) {
    return [System.Text.Encoding]::UTF8.GetString($response.Content)
  }
  return [string]$response.Content
}

function Assert-IamResourcesAbsent {
  $rolesXml = Get-LocalStackIamXml "ListRoles"
  $policiesXml = Get-LocalStackIamXml "ListPolicies" "&Scope=Local"
  $escapedPrefix = [regex]::Escape($uniquePrefix)
  if ($rolesXml -match "<RoleName>$escapedPrefix-") {
    throw " $uniquePrefix IAM role"
  }
  if ($policiesXml -match "<PolicyName>$escapedPrefix-") {
    throw " $uniquePrefix IAM policy"
  }
}

try {
  New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
  Copy-Item (Join-Path $candidateRoot "*") $workRoot -Recurse -Force
  Copy-Item (Join-Path $labRoot "fixtures") (Join-Path $scratchRoot "fixtures") -Recurse -Force
  Copy-Item (Join-Path $PSScriptRoot "catalog.tftest.hcl") (Join-Path $workRoot "catalog.tftest.hcl") -Force

  $source = (Get-ChildItem $workRoot -Recurse -Filter "*.tf" | Get-Content -Raw) -join "`n"
  if (@(Get-ChildItem $workRoot -Recurse -File -Filter '*.ps1').Count -ne 0) {
    throw 'Candidate work must contain Terraform HCL only.'
  }
  Assert-AwsProviderContract $source
  foreach ($needle in @(
      "aws_iam_policy_document",
      'module "access_role"',
      "for_each",
      "sensitive   = true",
      'precondition',
      'strcontains(action, "*")',
      'localhost|127\\.0\\.0\\.1|\\[::1\\]'
    )) {
    if ($source -notmatch [regex]::Escape($needle)) { throw "$needle" }
  }
  if ($source -match '(?i)permissions_boundary|max_session_duration|terraform_data|aws_dynamodb|aws_sns') {
    throw 'Candidate includes an IAM-domain or AWS-resource burden outside this challenge contract.'
  }
  $resourceTypes = @([regex]::Matches($source, '(?m)^\s*resource\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  if (($resourceTypes -join '|') -cne 'aws_iam_policy|aws_iam_role|aws_iam_role_policy_attachment') {
    throw 'Managed resources must be exactly IAM role, policy, and attachment.'
  }
  Set-Location $workRoot
  Invoke-Terraform @("fmt", "-check", "-recursive")
  Invoke-Terraform @("init", "-input=false", "-no-color")
  Invoke-Terraform @("validate", "-no-color")

  $testSource = [IO.File]::ReadAllText((Join-Path $workRoot 'catalog.tftest.hcl'))
  if ($testSource -match '(?i)mock_provider|override_(resource|data|module)' -or
      ([regex]::Matches($testSource, '(?m)^run\s+"')).Count -ne 8) {
    throw 'Canonical suite must contain exactly 8 Terraform 1.6 runs without mocks or overrides.'
  }

  $testOutput = @(& terraform test -no-color 2>&1)
  $testExit = $LASTEXITCODE
  $testOutput | ForEach-Object { Write-Host $_ }
  $testText = $testOutput -join "`n"
  if ($testExit -ne 0) { throw "canonical tests exit code=$testExit" }
  if ([regex]::Matches($testText, '(?m)^Success! 8 passed, 0 failed\.$').Count -ne 1) {
    throw " 8/8 canonical tests"
  }

  if ($UnitOnly) {
    Write-Host 'PASS challenge-26 UnitOnly (8/8 Terraform 1.6 runs)'
    return
  }

  $health = Invoke-RestMethod -UseBasicParsing -Uri ($LocalstackEndpoint + '/_localstack/health') -Method Get
  foreach ($service in @('iam', 'sts')) {
    if ($null -eq $health.services.$service -or [string]$health.services.$service -notmatch 'available|running') {
      throw "LocalStack service $service is unavailable."
    }
  }

  Remove-Item (Join-Path $workRoot "catalog.tftest.hcl") -Force
  $initialPlan = Join-Path $scratchRoot 'initial.tfplan'
  Invoke-Terraform @("plan", "-out=$initialPlan", "-input=false", "-no-color", "-var=name_prefix=$uniquePrefix", "-var=localstack_endpoint=$LocalstackEndpoint")
  $initialChanges = @(Get-PlanChanges $initialPlan)
  if ($initialChanges.Count -ne 9 -or @($initialChanges | Where-Object { (@($_.change.actions) -join ',') -ne 'create' }).Count -ne 0) {
    throw 'Initial saved plan must contain exactly 9 creates.'
  }
  Invoke-Terraform @("apply", "-auto-approve", "-input=false", "-no-color", $initialPlan)

  $roleKeys = (& terraform output -json role_keys | ConvertFrom-Json)
  if ($LASTEXITCODE -ne 0 -or $roleKeys.Count -ne 3) { throw " 3  $($roleKeys.Count)" }

  & terraform plan -detailed-exitcode -input=false -no-color "-var=name_prefix=$uniquePrefix" "-var=localstack_endpoint=$LocalstackEndpoint" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "apply  clean planexit code=$LASTEXITCODE" }

  & terraform plan -detailed-exitcode -input=false -no-color "-var=name_prefix=$uniquePrefix" "-var=localstack_endpoint=$LocalstackEndpoint" "-var=catalog_path=../fixtures/access-catalog-reordered.csv" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "CSV reorder must produce a zero-change plan, exit code=$LASTEXITCODE" }

  $roleName = "$uniquePrefix-payments-ledger"
  $policyArn = "arn:aws:iam::000000000000:policy/$uniquePrefix-payments-ledger-policy"
  & aws --endpoint-url $LocalstackEndpoint iam detach-role-policy --role-name $roleName --policy-arn $policyArn --no-cli-pager | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Unable to create real IAM attachment drift.' }

  $repairPlan = Join-Path $scratchRoot 'repair.tfplan'
  Invoke-Terraform @("plan", "-out=$repairPlan", "-input=false", "-no-color", "-var=name_prefix=$uniquePrefix", "-var=localstack_endpoint=$LocalstackEndpoint")
  $repairChanges = @(Get-PlanChanges $repairPlan)
  if ($repairChanges.Count -ne 1 -or $repairChanges[0].address -cne 'module.access_role["payments-ledger"].aws_iam_role_policy_attachment.this' -or
      (@($repairChanges[0].change.actions) -join ',') -cne 'create') {
    throw 'Repair plan must recreate only the drifted payments-ledger attachment.'
  }
  Invoke-Terraform @("apply", "-auto-approve", "-input=false", "-no-color", $repairPlan)

  & terraform plan -detailed-exitcode -input=false -no-color "-var=name_prefix=$uniquePrefix" "-var=localstack_endpoint=$LocalstackEndpoint" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "repair apply must end in a clean plan, exit code=$LASTEXITCODE" }
}
finally {
  try {
    if (Test-Path $workRoot) {
      Set-Location $workRoot
      if (Test-Path (Join-Path $workRoot "terraform.tfstate")) {
        $destroyOutput = @(& terraform destroy -auto-approve -input=false -no-color "-var=name_prefix=$uniquePrefix" "-var=localstack_endpoint=$LocalstackEndpoint" 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "cleanup destroy $($destroyOutput -join "`n")" }
      }
      Assert-IamResourcesAbsent
    }
  }
  finally {
    Set-Location $originalLocation
    Remove-Item $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "PASS challenge-26 (alignment A, difficulty 95/100): 8/8 Terraform 1.6 testssaved planCSV reorder IAM attachment drift repairclean/destroy "
