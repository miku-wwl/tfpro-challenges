[CmdletBinding()]
param(
  [switch]$AllowAnswers,
  [switch]$SkipTerraform
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$expected = 41..60
$expectedRuns = @{
  41 = 7
  42 = 7
  43 = 21
  44 = 9
  45 = 7
  46 = 8
  47 = 8
  48 = 15
  49 = 10
  50 = 19
  51 = 6
  52 = 7
  53 = 7
  54 = 8
  55 = 8
  56 = 13
  57 = 13
  58 = 11
  59 = 20
  60 = 16
}
$allowedResources = @(
  'aws_autoscaling_group',
  'aws_iam_instance_profile',
  'aws_iam_policy',
  'aws_iam_role',
  'aws_iam_role_policy_attachment',
  'aws_instance',
  'aws_launch_template',
  'aws_s3_bucket',
  'aws_s3_object',
  'aws_security_group',
  'aws_security_group_rule',
  'aws_vpc_security_group_ingress_rule',
  'random_integer'
)
$allowedData = @(
  'aws_ami',
  'aws_caller_identity',
  'aws_iam_policy_document',
  'aws_iam_session_context',
  'aws_subnet',
  'terraform_remote_state'
)
$failures = New-Object System.Collections.Generic.List[string]
$runTotal = 0

foreach ($number in $expected) {
  $challenge = Join-Path $root "challenge-$number"
  if (-not (Test-Path -LiteralPath $challenge -PathType Container)) {
    $failures.Add("challenge-$number is missing")
    continue
  }

  $allowedTopDirectories = @('fixtures', 'starter', 'tests')
  if ($AllowAnswers) { $allowedTopDirectories += 'answer' }
  $unexpectedDirectories = @(
    Get-ChildItem -LiteralPath $challenge -Directory -Force |
      Where-Object { $_.Name -notin $allowedTopDirectories }
  )
  $unexpectedFiles = @(
    Get-ChildItem -LiteralPath $challenge -File -Force |
      Where-Object { $_.Name -notin @('Readme.md', 'lab.yaml') }
  )
  if ($unexpectedDirectories.Count -ne 0 -or $unexpectedFiles.Count -ne 0) {
    $failures.Add("challenge-$number has unexpected top-level files or directories")
  }

  foreach ($required in @('Readme.md', 'lab.yaml', 'fixtures', 'starter', 'tests', 'tests\grade.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $challenge $required))) {
      $failures.Add("challenge-$number missing $required")
    }
  }
  if ($failures | Where-Object { $_ -like "challenge-$number missing*" }) {
    continue
  }

  $lab = Get-Content -LiteralPath (Join-Path $challenge 'lab.yaml') -Raw -Encoding UTF8
  if ($lab -notmatch '(?m)^score(?:_vs_tf_pro)?:\s*95\s*$') {
    $failures.Add("challenge-$number score is not 95")
  }
  if ($lab -notmatch '(?m)^alignment:\s*A-?\s*$') {
    $failures.Add("challenge-$number alignment is not A/A-")
  }
  if ($lab -notmatch '(?m)terraform(?:_version)?:[^\r\n]*1\.6') {
    $failures.Add("challenge-$number does not declare Terraform 1.6")
  }
  $readme = Get-Content -LiteralPath (Join-Path $challenge 'Readme.md') -Raw -Encoding UTF8
  if ($readme -notmatch '(?m)^.{0,120}95\s*/\s*100') {
    $failures.Add("challenge-$number Readme does not declare difficulty 95/100")
  }
  if ($readme -notmatch '(?m)^.{0,160}\*\*A-?\*\*') {
    $failures.Add("challenge-$number Readme does not declare alignment A/A-")
  }
  if ($readme -notmatch '(?i)LocalStack' -or $readme -notmatch '1\.6\.6') {
    $failures.Add("challenge-$number Readme does not declare the LocalStack/Terraform 1.6.6 runtime")
  }

  $starter = Join-Path $challenge 'starter'
  $candidateFiles = @(Get-ChildItem -LiteralPath $starter -Recurse -File)
  if ($candidateFiles.Count -eq 0 -or @($candidateFiles | Where-Object { $_.Extension -ne '.tf' }).Count -ne 0) {
    $failures.Add("challenge-$number starter must contain HCL only")
  }
  $candidateText = ($candidateFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
  if ($candidateText -notmatch '(?i)TODO') {
    $failures.Add("challenge-$number starter has no unfinished marker")
  }
  $providerCount = [regex]::Matches($candidateText, '(?m)^\s*provider\s+"aws"\s*\{').Count
  if ($providerCount -eq 0 -or
      [regex]::Matches($candidateText, '(?m)^\s*access_key\s*=\s*"test"\s*$').Count -lt $providerCount -or
      [regex]::Matches($candidateText, '(?m)^\s*secret_key\s*=\s*"test"\s*$').Count -lt $providerCount -or
      [regex]::Matches($candidateText, '(?m)^\s*skip_credentials_validation\s*=\s*true\s*$').Count -lt $providerCount -or
      [regex]::Matches($candidateText, '(?m)^\s*skip_metadata_api_check\s*=\s*true\s*$').Count -lt $providerCount -or
      [regex]::Matches($candidateText, '(?m)^\s*skip_requesting_account_id\s*=\s*true\s*$').Count -lt $providerCount -or
      [regex]::Matches($candidateText, '(?m)^\s*endpoints\s*\{').Count -lt $providerCount) {
    $failures.Add("challenge-$number starter AWS provider safety contract is incomplete")
  }

  $resources = @(
    [regex]::Matches($candidateText, 'resource\s+"([a-z0-9_]+)"') |
      ForEach-Object { $_.Groups[1].Value } |
      Sort-Object -Unique
  )
  $dataSources = @(
    [regex]::Matches($candidateText, 'data\s+"([a-z0-9_]+)"') |
      ForEach-Object { $_.Groups[1].Value } |
      Sort-Object -Unique
  )
  foreach ($type in $resources) {
    if ($type -notin $allowedResources) {
      $failures.Add("challenge-$number unsupported resource $type")
    }
  }
  foreach ($type in $dataSources) {
    if ($type -notin $allowedData) {
      $failures.Add("challenge-$number unsupported data source $type")
    }
  }

  if ($AllowAnswers) {
    $answer = Join-Path $challenge 'answer'
    if (-not (Test-Path -LiteralPath $answer -PathType Container)) {
      $failures.Add("challenge-$number answer is missing during pre-delivery audit")
    }
    else {
      $answerFiles = @(Get-ChildItem -LiteralPath $answer -Recurse -File)
      if ($answerFiles.Count -eq 0 -or @($answerFiles | Where-Object { $_.Extension -ne '.tf' }).Count -ne 0) {
        $failures.Add("challenge-$number answer must contain HCL only")
      }
      $answerText = ($answerFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
      if ($answerText -match '(?i)TODO|mock_provider|override_(?:resource|data|module)|ignore_changes') {
        $failures.Add("challenge-$number answer contains an unfinished or prohibited construct")
      }
      $answerProviderCount = [regex]::Matches($answerText, '(?m)^\s*provider\s+"aws"\s*\{').Count
      if ($answerProviderCount -eq 0 -or
          [regex]::Matches($answerText, '(?m)^\s*access_key\s*=\s*"test"\s*$').Count -lt $answerProviderCount -or
          [regex]::Matches($answerText, '(?m)^\s*secret_key\s*=\s*"test"\s*$').Count -lt $answerProviderCount -or
          [regex]::Matches($answerText, '(?m)^\s*skip_credentials_validation\s*=\s*true\s*$').Count -lt $answerProviderCount -or
          [regex]::Matches($answerText, '(?m)^\s*skip_metadata_api_check\s*=\s*true\s*$').Count -lt $answerProviderCount -or
          [regex]::Matches($answerText, '(?m)^\s*skip_requesting_account_id\s*=\s*true\s*$').Count -lt $answerProviderCount -or
          [regex]::Matches($answerText, '(?m)^\s*endpoints\s*\{').Count -lt $answerProviderCount) {
        $failures.Add("challenge-$number answer AWS provider safety contract is incomplete")
      }
      $answerResources = @(
        [regex]::Matches($answerText, 'resource\s+"([a-z0-9_]+)"') |
          ForEach-Object { $_.Groups[1].Value } |
          Sort-Object -Unique
      )
      $answerDataSources = @(
        [regex]::Matches($answerText, 'data\s+"([a-z0-9_]+)"') |
          ForEach-Object { $_.Groups[1].Value } |
          Sort-Object -Unique
      )
      foreach ($type in $answerResources) {
        if ($type -notin $allowedResources) {
          $failures.Add("challenge-$number answer has unsupported resource $type")
        }
      }
      foreach ($type in $answerDataSources) {
        if ($type -notin $allowedData) {
          $failures.Add("challenge-$number answer has unsupported data source $type")
        }
      }
    }
  }

  $fixtures = Join-Path $challenge 'fixtures'
  if (Test-Path -LiteralPath $fixtures -PathType Container) {
    $fixtureTfFiles = @(Get-ChildItem -LiteralPath $fixtures -Recurse -File -Filter '*.tf')
    $fixtureText = ($fixtureTfFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
    $fixtureResources = @(
      [regex]::Matches($fixtureText, 'resource\s+"([a-z0-9_]+)"') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
    )
    $fixtureDataSources = @(
      [regex]::Matches($fixtureText, 'data\s+"([a-z0-9_]+)"') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique
    )
    foreach ($type in $fixtureResources) {
      if ($type -notin $allowedResources) {
        $failures.Add("challenge-$number fixture has unsupported resource $type")
      }
    }
    foreach ($type in $fixtureDataSources) {
      if ($type -notin $allowedData) {
        $failures.Add("challenge-$number fixture has unsupported data source $type")
      }
    }
  }

  $tests = @(Get-ChildItem -LiteralPath (Join-Path $challenge 'tests') -File -Filter '*.tftest.hcl')
  $challengeRuns = 0
  if ($tests.Count -eq 0) {
    $failures.Add("challenge-$number has no canonical tests")
  }
  foreach ($test in $tests) {
    $testText = Get-Content -LiteralPath $test.FullName -Raw
    $challengeRuns += [regex]::Matches($testText, '(?m)^\s*run\s+"').Count
    if ($testText -match '(?m)^\s*(mock_provider|override_(?:resource|data|module))\b') {
      $failures.Add("challenge-$number uses mock/override")
    }
  }
  $runTotal += $challengeRuns
  if ($challengeRuns -ne $expectedRuns[$number]) {
    $failures.Add("challenge-$number canonical run count is $challengeRuns; expected $($expectedRuns[$number])")
  }

  $grader = Join-Path $challenge 'tests\grade.ps1'
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($grader, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -ne 0) {
    $failures.Add("challenge-$number grader has PowerShell parse errors")
  }
  if (@([IO.File]::ReadAllBytes($grader) | Where-Object { $_ -gt 127 }).Count -ne 0) {
    $failures.Add("challenge-$number grader is not ASCII-only")
  }
  $graderText = Get-Content -LiteralPath $grader -Raw
  if ($graderText -notmatch '1\.6\.6' -or $graderText -notmatch '(?i)UnitOnly') {
    $failures.Add("challenge-$number grader does not enforce Terraform 1.6.6 and UnitOnly")
  }
  $endpointMatch = [regex]::Match(
    $graderText,
    '(?mi)^\s*Assert-(?:Endpoint|LoopbackEndpoint|LoopbackOrigin)\s+\$'
  )
  $resolveMatch = [regex]::Match($graderText, '(?mi)^.*Resolve-Path')
  if (-not $endpointMatch.Success -or -not $resolveMatch.Success -or $endpointMatch.Index -gt $resolveMatch.Index) {
    $failures.Add("challenge-$number endpoint guard is not endpoint-first")
  }

  Get-ChildItem -LiteralPath $challenge -Recurse -File -Filter '*.json' | ForEach-Object {
    try {
      Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null
    }
    catch {
      $failures.Add("challenge-$number invalid JSON fixture $($_.Name)")
    }
  }

  if (-not $AllowAnswers -and (Test-Path -LiteralPath (Join-Path $challenge 'answer'))) {
    $failures.Add("challenge-$number still contains answer")
  }
  $artifacts = @(
    Get-ChildItem -LiteralPath $challenge -Recurse -Force |
      Where-Object {
        $_.Name -eq '.terraform' -or
        $_.Name -eq '.terraform.lock.hcl' -or
        $_.Name -match '(\.tfstate(?:\.backup)?$|\.tfplan$|\.lock\.info$|crash\.log$)'
      }
  )
  if ($artifacts.Count -ne 0) {
    $failures.Add("challenge-$number contains Terraform runtime artifacts")
  }

  if (-not $SkipTerraform) {
    & terraform fmt -check -recursive $challenge *> $null
    if ($LASTEXITCODE -ne 0) {
      $failures.Add("challenge-$number terraform fmt failed")
    }
  }
}

[pscustomobject]@{
  challenges     = $expected.Count
  canonical_runs = $runTotal
  failures       = @($failures)
} | ConvertTo-Json -Depth 4

if ($failures.Count -ne 0) {
  exit 1
}
