[CmdletBinding()]
param(
  [string]$Candidate='',
  [string]$LocalstackEndpoint='http://localhost:4566',
  [switch]$UnitOnly
)
if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Assert-Endpoint([string]$Value) {
  if ($Value -notmatch '^https?://(?:localhost|127\.0\.0\.1|\[::1\]):[0-9]{1,5}$') { throw "Unsafe LocalStack endpoint: $Value" }
  $uri = [Uri]$Value
  if ($uri.DnsSafeHost -notin @('localhost','127.0.0.1','::1') -or $uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment -or $uri.UserInfo -or $uri.Port -lt 1 -or $uri.Port -gt 65535) { throw "Unsafe LocalStack endpoint: $Value" }
}
function Native([string]$File,[string[]]$Arguments,[int[]]$Allowed=@(0),[switch]$Quiet) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $lines = @(& $File @Arguments 2>&1 | ForEach-Object { "$_" }); $code = $LASTEXITCODE
  $ErrorActionPreference = $old; $joined = $lines -join "`n"
  if (-not $Quiet -and $lines.Count -gt 0) { $lines | Out-Host }
  if ($code -notin $Allowed) { throw "$File $($Arguments -join ' ') failed ($code).`n$joined" }
  [pscustomobject]@{ Code=$code; Text=$joined }
}
function Tf([string]$Dir,[string[]]$Arguments,[int[]]$Allowed=@(0),[switch]$Quiet) { Native 'terraform' (@("-chdir=$Dir")+$Arguments) $Allowed -Quiet:$Quiet }
function Aws([string[]]$Arguments,[int[]]$Allowed=@(0),[switch]$Quiet) { Native 'aws.exe' (@('--endpoint-url',$LocalstackEndpoint,'--region','us-east-1')+$Arguments) $Allowed -Quiet:$Quiet }
function Copy-Clean([string]$Source,[string]$Destination) {
  New-Item -ItemType Directory -Force $Destination | Out-Null
  foreach ($i in Get-ChildItem -LiteralPath $Source -Force) {
    if ($i.Name -in @('.terraform','.terraform.lock.hcl','terraform.tfstate','terraform.tfstate.backup','.terraform.tfstate.lock.info') -or $i.Extension -in @('.tfplan','.tfstate')) { continue }
    if ($i.PSIsContainer) { Copy-Clean $i.FullName (Join-Path $Destination $i.Name) } else { Copy-Item -LiteralPath $i.FullName -Destination (Join-Path $Destination $i.Name) -Force }
  }
}
function Write-Backend([string]$Path,[string]$Bucket,[string]$Key){[IO.File]::WriteAllText($Path,@"
bucket = "$Bucket"
key = "$Key"
region = "us-east-1"
access_key = "test"
secret_key = "test"
use_path_style = true
skip_credentials_validation = true
skip_metadata_api_check = true
skip_requesting_account_id = true
endpoints = { s3 = "$LocalstackEndpoint" }
"@,[Text.UTF8Encoding]::new($false))}
function Exact-Tests([string]$Dir,[string]$File,[int]$Expected) {
  New-Item -ItemType Directory -Force (Join-Path $Dir 'tests') | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot $File) -Destination (Join-Path $Dir "tests\$File") -Force
  $r = Tf $Dir @('test','-test-directory=tests','-no-color')
  if ([regex]::Matches($r.Text,"(?m)^Success!\s+$Expected passed,\s+0 failed\.\s*$").Count -ne 1 -or [regex]::Matches($r.Text,'(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne $Expected) { throw "Expected exact $Expected Terraform 1.6 runs for $File." }
  Remove-Item -LiteralPath (Join-Path $Dir 'tests') -Recurse -Force
}
function Plan-Json([string]$Dir,[string]$Plan) { ((Tf $Dir @('show','-json',$Plan) -Quiet).Text | ConvertFrom-Json) }
function Assert-Changes($Doc,[hashtable]$Expected,[string]$Label) {
  $actual = @{}
  foreach ($c in @($Doc.resource_changes | Where-Object { [string]$_.address -notlike 'data.*' })) { $a = @($c.change.actions) -join ','; if ($a -ne 'no-op') { $actual[[string]$c.address] = $a } }
  if ($actual.Count -ne $Expected.Count) { throw "$Label expected $($Expected.Count) changes, got $($actual.Count): $($actual.Keys -join ', ')" }
  foreach ($k in $Expected.Keys) { if (-not $actual.ContainsKey($k) -or $actual[$k] -ne $Expected[$k]) { throw "$Label expected $k=$($Expected[$k]); got $($actual[$k])." } }
}

Assert-Endpoint $LocalstackEndpoint
$terraformVersion = ((Native 'terraform' @('version','-json') -Quiet).Text | ConvertFrom-Json).terraform_version
if ($terraformVersion -ne '1.6.6') { throw "Terraform 1.6.6 is required; active version is $terraformVersion." }
$candidate = (Resolve-Path -LiteralPath $Candidate).Path
$foundationSource = Join-Path $candidate 'foundation'
$deliverySource = Join-Path $candidate 'delivery'
if (-not (Test-Path $foundationSource) -or -not (Test-Path $deliverySource)) { throw 'Candidate must contain foundation and delivery roots.' }
$files = @(Get-ChildItem -LiteralPath $candidate -Recurse -File)
if (@($files | Where-Object Extension -ne '.tf').Count -ne 0) { throw 'Candidate must contain Terraform HCL only.' }
$all = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($all -match '(?i)\b(TODO|terraform_data|mock_provider|override_data|override_resource|aws_sns_|aws_vpc|aws_subnets)\b|ignore_changes') { throw 'Forbidden starter, synthetic, mock, SNS, or VPC construct found.' }
if ([regex]::Matches($all,'required_version\s*=\s*"~> 1\.6"').Count -ne 2 -or [regex]::Matches($all,'backend\s+"s3"\s*\{\s*\}').Count -ne 2) { throw 'Both roots need Terraform ~>1.6 and empty partial S3 backends.' }
$ftext = (Get-ChildItem $foundationSource -Filter *.tf | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$dtext = (Get-ChildItem $deliverySource -Filter *.tf | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
$fr = @([regex]::Matches($ftext,'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$dr = @([regex]::Matches($dtext,'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($fr -join ',') -ne 'aws_s3_bucket,aws_s3_object') { throw "Foundation resources are not exact: $($fr -join ',')" }
if (($dr -join ',') -ne 'aws_iam_policy,aws_iam_role,aws_iam_role_policy_attachment') { throw "Delivery resources are not exact: $($dr -join ',')" }
if ($dtext -notmatch 'data\s+"terraform_remote_state"\s+"foundation"' -or $dtext -notmatch 'backend\s*=\s*"s3"' -or $dtext -notmatch 'data\s+"aws_iam_policy_document"') { throw 'Delivery remote-state/IAM data contract is incomplete.' }
foreach ($t in @('access_key','secret_key','use_path_style','skip_credentials_validation','skip_metadata_api_check','skip_requesting_account_id','endpoints')) { if ($dtext -notmatch "(?m)^\s*$t\s*=") { throw "Remote-state config misses $t." } }
$ft = Get-Content -Raw (Join-Path $PSScriptRoot 'foundation.tftest.hcl')
$dt = Get-Content -Raw (Join-Path $PSScriptRoot 'delivery.tftest.hcl')
if (($ft+$dt) -match '(?i)mock_provider|override_' -or [regex]::Matches($ft,'(?m)^run\s+"').Count -ne 8 -or [regex]::Matches($dt,'(?m)^run\s+"').Count -ne 7) { throw 'Canonical tests must be exact 8+7 normal Terraform 1.6 runs.' }

$suffix = ([Guid]::NewGuid().ToString('N')).Substring(0,10)
$runId = "c48-$suffix"; $stateBucket = "tfpro-c48-state-$suffix"
$temp = Join-Path ([IO.Path]::GetTempPath()) "tfpro-c48-$suffix"
$candidateWork = Join-Path $temp 'candidate'
$fw = Join-Path $candidateWork 'foundation'; $dw = Join-Path $candidateWork 'delivery'
$foundationUp = $false; $deliveryUp = $false; $failure = $null; $revision = 'v1'
$saved = @{}
foreach ($n in @('AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_DEFAULT_REGION','AWS_EC2_METADATA_DISABLED','AWS_PAGER','TF_VAR_run_id','TF_VAR_state_bucket','TF_VAR_expected_revision','TF_VAR_localstack_endpoint')) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
try {
  try { Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null } catch { throw 'LocalStack is unavailable.' }
  $env:AWS_ACCESS_KEY_ID='test'; $env:AWS_SECRET_ACCESS_KEY='test'; $env:AWS_DEFAULT_REGION='us-east-1'; $env:AWS_EC2_METADATA_DISABLED='true'; $env:AWS_PAGER=''
  $env:TF_VAR_run_id=$runId; $env:TF_VAR_state_bucket=$stateBucket; $env:TF_VAR_expected_revision='v1'; $env:TF_VAR_localstack_endpoint=$LocalstackEndpoint
  Copy-Clean $foundationSource $fw; Copy-Clean $deliverySource $dw
  Copy-Clean (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $temp 'fixtures')
  Aws @('s3api','create-bucket','--bucket',$stateBucket) -Quiet | Out-Null
  $fb = Join-Path $temp 'foundation.backend.hcl'; $db = Join-Path $temp 'delivery.backend.hcl'
  Write-Backend $fb $stateBucket 'foundation/terraform.tfstate'; Write-Backend $db $stateBucket 'delivery/terraform.tfstate'
  Tf $fw @('fmt','-check','-recursive') | Out-Null; Tf $dw @('fmt','-check','-recursive') | Out-Null
  Tf $fw @('init','-input=false','-no-color',"-backend-config=$fb") | Out-Null; Tf $fw @('validate','-no-color') | Out-Null; Exact-Tests $fw 'foundation.tftest.hcl' 8
  $fcommon = @('-input=false','-no-color',"-var=run_id=$runId","-var=localstack_endpoint=$LocalstackEndpoint")
  $fplan = Join-Path $fw 'v1.tfplan'; Tf $fw (@('plan',"-out=$fplan")+$fcommon+@('-var=catalog_path=../../fixtures/artifacts-v1.json')) | Out-Null
  Assert-Changes (Plan-Json $fw $fplan) @{'aws_s3_bucket.artifacts'='create';'aws_s3_object.artifact["api"]'='create';'aws_s3_object.artifact["worker"]'='create'} 'Foundation v1 saved plan'
  Tf $fw @('apply','-input=false','-no-color',$fplan) | Out-Null; $foundationUp = $true
  Tf $dw @('init','-input=false','-no-color',"-backend-config=$db") | Out-Null; Tf $dw @('validate','-no-color') | Out-Null; Exact-Tests $dw 'delivery.tftest.hcl' 7
  Write-Host '[unit] foundation 8/8 and delivery 7/7 normal Terraform 1.6 runs passed.'
  $dcommon = @('-input=false','-no-color',"-var=run_id=$runId","-var=state_bucket=$stateBucket",'-var=expected_revision=v1',"-var=localstack_endpoint=$LocalstackEndpoint",'-var=manifest_path=../../fixtures/grants.json')
  if ($UnitOnly) {
    Tf $fw (@('destroy','-auto-approve')+$fcommon+@('-var=catalog_path=../../fixtures/artifacts-v1.json')) | Out-Null; $foundationUp = $false
    Aws @('s3','rb',"s3://$stateBucket",'--force') -Quiet | Out-Null; $stateBucket = $null
    Write-Host 'PASS challenge-48 UnitOnly'; return
  }
  $dplan = Join-Path $dw 'v1.tfplan'; Tf $dw (@('plan',"-out=$dplan")+$dcommon) | Out-Null
  Assert-Changes (Plan-Json $dw $dplan) @{'aws_iam_role.consumer'='create';'aws_iam_policy.consumer'='create';'aws_iam_role_policy_attachment.consumer'='create'} 'Delivery v1 saved plan'
  Tf $dw @('apply','-input=false','-no-color',$dplan) | Out-Null; $deliveryUp = $true
  $keys = @(((Aws @('s3api','list-objects-v2','--bucket',$stateBucket,'--query','Contents[].Key','--output','text') -Quiet).Text -split '\s+' | Where-Object { $_ } | Sort-Object))
  if (($keys -join ',') -ne 'delivery/terraform.tfstate,foundation/terraform.tfstate') { throw "Unexpected state keys: $($keys -join ',')" }
  $fc = Tf $fw (@('plan','-detailed-exitcode')+$fcommon+@('-var=catalog_path=../../fixtures/artifacts-v1.json')) @(0,2) -Quiet
  $dc = Tf $dw (@('plan','-detailed-exitcode')+$dcommon) @(0,2) -Quiet
  if ($fc.Code -ne 0 -or $dc.Code -ne 0) { throw 'Post-apply roots are not clean.' }
  $fr = Tf $fw (@('plan','-detailed-exitcode')+$fcommon+@('-var=catalog_path=../../fixtures/artifacts-v1-reordered.json')) @(0,2) -Quiet
  $drp = Tf $dw (@('plan','-detailed-exitcode')+($dcommon | Where-Object { $_ -notlike '-var=manifest_path=*' })+@('-var=manifest_path=../../fixtures/grants-reordered.json')) @(0,2) -Quiet
  if ($fr.Code -ne 0 -or $drp.Code -ne 0) { throw 'Catalog or grant reorder changed the graph.' }
  $body = Join-Path $temp 'drift.txt'; [IO.File]::WriteAllText($body,'manual drift',[Text.UTF8Encoding]::new($false))
  Aws @('s3api','put-object','--bucket',"tfpro-c48-artifacts-$runId",'--key','releases/api.txt','--body',$body) -Quiet | Out-Null
  $repairPlan = Join-Path $fw 'repair.tfplan'; $rp = Tf $fw (@('plan','-detailed-exitcode',"-out=$repairPlan")+$fcommon+@('-var=catalog_path=../../fixtures/artifacts-v1.json')) @(0,2) -Quiet
  if ($rp.Code -ne 2) { throw 'Foundation object drift was not detected.' }
  Assert-Changes (Plan-Json $fw $repairPlan) @{'aws_s3_object.artifact["api"]'='update'} 'Foundation drift repair'; Tf $fw @('apply','-input=false','-no-color',$repairPlan) | Out-Null
  $v2plan = Join-Path $fw 'v2.tfplan'; Tf $fw (@('plan',"-out=$v2plan")+$fcommon+@('-var=catalog_path=../../fixtures/artifacts-v2.json')) | Out-Null
  Assert-Changes (Plan-Json $fw $v2plan) @{'aws_s3_object.artifact["api"]'='update';'aws_s3_object.artifact["worker"]'='update'} 'Foundation v2 saved plan'; Tf $fw @('apply','-input=false','-no-color',$v2plan) | Out-Null; $revision = 'v2'
  $stale = Tf $dw (@('plan')+$dcommon) @(0,1) -Quiet
  if ($stale.Code -ne 1 -or $stale.Text -notmatch 'remote artifact contract') { throw 'Stale delivery revision was not rejected.' }
  $d2common = @($dcommon | ForEach-Object { if ($_ -eq '-var=expected_revision=v1') { '-var=expected_revision=v2' } else { $_ } })
  $d2plan = Join-Path $dw 'v2.tfplan'; Tf $dw (@('plan',"-out=$d2plan")+$d2common) | Out-Null
  Assert-Changes (Plan-Json $dw $d2plan) @{'aws_iam_role.consumer'='update';'aws_iam_policy.consumer'='update'} 'Delivery v2 saved plan'; Tf $dw @('apply','-input=false','-no-color',$d2plan) | Out-Null
  $contract = ((Tf $dw @('output','-json','access_contract') -Quiet).Text | ConvertFrom-Json)
  Aws @('iam','detach-role-policy','--role-name',$contract.role_name,'--policy-arn',$contract.policy_arn) -Quiet | Out-Null
  $idrift = Join-Path $dw 'drift.tfplan'; $ip = Tf $dw (@('plan','-detailed-exitcode',"-out=$idrift")+$d2common) @(0,2) -Quiet
  if ($ip.Code -ne 2) { throw 'IAM attachment drift was not detected.' }
  Assert-Changes (Plan-Json $dw $idrift) @{'aws_iam_role_policy_attachment.consumer'='create'} 'IAM drift repair'; Tf $dw @('apply','-input=false','-no-color',$idrift) | Out-Null
  if ((Tf $fw (@('plan','-detailed-exitcode')+$fcommon+@('-var=catalog_path=../../fixtures/artifacts-v2.json')) @(0,2) -Quiet).Code -ne 0 -or (Tf $dw (@('plan','-detailed-exitcode')+$d2common) @(0,2) -Quiet).Code -ne 0) { throw 'Final roots are not clean.' }
  $ddestroy = Join-Path $dw 'destroy.tfplan'; Tf $dw (@('plan','-destroy',"-out=$ddestroy")+$d2common) | Out-Null
  Assert-Changes (Plan-Json $dw $ddestroy) @{'aws_iam_role.consumer'='delete';'aws_iam_policy.consumer'='delete';'aws_iam_role_policy_attachment.consumer'='delete'} 'Delivery destroy'; Tf $dw @('apply','-input=false','-no-color',$ddestroy) | Out-Null; $deliveryUp = $false
  $fdestroy = Join-Path $fw 'destroy.tfplan'; Tf $fw (@('plan','-destroy',"-out=$fdestroy")+$fcommon+@('-var=catalog_path=../../fixtures/artifacts-v2.json')) | Out-Null
  Assert-Changes (Plan-Json $fw $fdestroy) @{'aws_s3_bucket.artifacts'='delete';'aws_s3_object.artifact["api"]'='delete';'aws_s3_object.artifact["worker"]'='delete'} 'Foundation destroy'; Tf $fw @('apply','-input=false','-no-color',$fdestroy) | Out-Null; $foundationUp = $false
  $role = Aws @('iam','get-role','--role-name',"tfpro-c48-$runId") @(0,254) -Quiet
  if ($role.Code -ne 254 -or $role.Text -notmatch 'NoSuchEntity') { throw 'IAM role residue remains.' }
  $artifact = Aws @('s3api','head-bucket','--bucket',"tfpro-c48-artifacts-$runId") @(0,254) -Quiet
  if ($artifact.Code -ne 254 -or $artifact.Text -notmatch '404|Not Found|NoSuchBucket') { throw 'Artifact bucket residue remains.' }
  Aws @('s3','rb',"s3://$stateBucket",'--force') -Quiet | Out-Null; $stateBucket = $null
  Write-Host '[e2e] dual S3 state keys, audited artifact/IAM plans, reorder, S3/IAM drift repair, revision propagation, ordered saved destroy, and zero residue passed.'
  Write-Host 'PASS challenge-48 (difficulty 95/100, alignment A)'
} catch { $failure = $_ } finally {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  if ($deliveryUp -and (Test-Path $dw)) { & terraform "-chdir=$dw" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" "-var=state_bucket=$stateBucket" "-var=expected_revision=$revision" "-var=localstack_endpoint=$LocalstackEndpoint" '-var=manifest_path=../../fixtures/grants.json' 2>$null | Out-Null }
  if ($foundationUp -and (Test-Path $fw)) { & terraform "-chdir=$fw" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" "-var=localstack_endpoint=$LocalstackEndpoint" "-var=catalog_path=../../fixtures/artifacts-$revision.json" 2>$null | Out-Null }
  if ($stateBucket) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 s3 rb "s3://$stateBucket" --force 2>$null | Out-Null }
  foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n,$saved[$n]) }
  if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
  $ErrorActionPreference = $old
}
if ($failure) { throw $failure }
