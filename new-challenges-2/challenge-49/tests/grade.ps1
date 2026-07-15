[CmdletBinding()]
param(
  [string]$Candidate='',
  [string]$LocalstackEndpoint='http://localhost:4566',
  [switch]$UnitOnly
)
if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Assert-Endpoint([string]$v) {
  if ($v -notmatch '^https?://(?:localhost|127\.0\.0\.1|\[::1\]):[0-9]{1,5}$') { throw "Unsafe endpoint: $v" }
  $u=[Uri]$v
  if ($u.DnsSafeHost -notin @('localhost','127.0.0.1','::1') -or $u.AbsolutePath -ne '/' -or $u.Query -or $u.Fragment -or $u.UserInfo -or $u.Port -lt 1 -or $u.Port -gt 65535) { throw "Unsafe endpoint: $v" }
}
function Native([string]$f,[string[]]$a,[int[]]$ok=@(0),[switch]$Quiet) {
  $old=$ErrorActionPreference; $ErrorActionPreference='Continue'; $lines=@(& $f @a 2>&1 | ForEach-Object { "$_" }); $code=$LASTEXITCODE; $ErrorActionPreference=$old; $t=$lines -join "`n"
  if (-not $Quiet -and $lines.Count -gt 0) { $lines | Out-Host }
  if ($code -notin $ok) { throw "$f $($a -join ' ') failed ($code).`n$t" }
  [pscustomobject]@{Code=$code;Text=$t}
}
function Tf([string]$d,[string[]]$a,[int[]]$ok=@(0),[switch]$Quiet) { Native terraform (@("-chdir=$d")+$a) $ok -Quiet:$Quiet }
function Aws([string]$r,[string[]]$a,[int[]]$ok=@(0),[switch]$Quiet) { Native aws.exe (@('--endpoint-url',$LocalstackEndpoint,'--region',$r)+$a) $ok -Quiet:$Quiet }
function Copy-Clean([string]$s,[string]$d) {
  New-Item -ItemType Directory -Force $d | Out-Null
  foreach ($i in Get-ChildItem -LiteralPath $s -Force) { if ($i.Name -in @('.terraform','.terraform.lock.hcl','terraform.tfstate','terraform.tfstate.backup','.terraform.tfstate.lock.info') -or $i.Extension -in @('.tfplan','.tfstate')) { continue }; if ($i.PSIsContainer) { Copy-Clean $i.FullName (Join-Path $d $i.Name) } else { Copy-Item -LiteralPath $i.FullName -Destination (Join-Path $d $i.Name) -Force } }
}
function PlanDoc([string]$d,[string]$p) { ((Tf $d @('show','-json',$p) -Quiet).Text | ConvertFrom-Json) }
function AssertChanges($doc,[hashtable]$expected,[string]$label) {
  $actual=@{}; foreach ($c in @($doc.resource_changes | Where-Object { [string]$_.address -notlike 'data.*' })) { $a=@($c.change.actions) -join ','; if ($a -ne 'no-op') { $actual[[string]$c.address]=$a } }
  if ($actual.Count -ne $expected.Count) { throw "$label expected $($expected.Count), got $($actual.Count): $($actual.Keys -join ', ')" }
  foreach ($k in $expected.Keys) { if (-not $actual.ContainsKey($k) -or $actual[$k] -ne $expected[$k]) { throw "$label expected $k=$($expected[$k]); got $($actual[$k])." } }
}
function ExactTests([string]$d) { $r=Tf $d @('test','-test-directory=tests','-no-color'); if ([regex]::Matches($r.Text,'(?m)^Success!\s+10 passed,\s+0 failed\.\s*$').Count -ne 1 -or [regex]::Matches($r.Text,'(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 10) { throw 'Expected exact 10/10 Terraform 1.6 runs.' } }

Assert-Endpoint $LocalstackEndpoint
$terraformVersion=((Native 'terraform' @('version','-json') -Quiet).Text|ConvertFrom-Json).terraform_version
if($terraformVersion -ne '1.6.6'){throw "Terraform 1.6.6 is required; active version is $terraformVersion."}
$candidate=(Resolve-Path -LiteralPath $Candidate).Path
$files=@(Get-ChildItem -LiteralPath $candidate -Recurse -File)
if (@($files | Where-Object Extension -ne '.tf').Count -ne 0) { throw 'Candidate must contain HCL only.' }
$text=($files | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n"
if ($text -match '(?i)\b(TODO|terraform_data|mock_provider|override_data|override_resource|aws_sns_|aws_vpc|aws_subnets|aws_ami)\b|ignore_changes') { throw 'Forbidden synthetic, mock, VPC discovery, AMI data, or drift suppression found.' }
$res=@([regex]::Matches($text,'resource\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$data=@([regex]::Matches($text,'data\s+"(aws_[a-z0-9_]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
if (($res -join ',') -ne 'aws_iam_instance_profile,aws_iam_role,aws_instance,aws_launch_template') { throw "Unexpected resources: $($res -join ',')" }
if (($data -join ',') -ne 'aws_subnet') { throw "Only data.aws_subnet is allowed; got $($data -join ',')" }
if ([regex]::Matches($text,'provider\s+"aws"\s*\{').Count -ne 2 -or $text -notmatch 'alias\s*=\s*"dr"' -or $text -notmatch 'module\s+"dr"[\s\S]*?aws\s*=\s*aws\.dr') { throw 'Dual provider routing is incomplete.' }
if ($text -notmatch 'replace_triggered_by\s*=\s*\[aws_launch_template\.replica\[each\.key\]\]') { throw 'Official launch-template replacement trigger is required.' }
$tests=Get-Content -Raw (Join-Path $PSScriptRoot 'canonical.tftest.hcl')
if ($tests -match '(?i)mock_provider|override_' -or [regex]::Matches($tests,'(?m)^run\s+"').Count -ne 10) { throw 'Canonical suite must have 10 normal Terraform 1.6 runs.' }

$runId='c49-'+([Guid]::NewGuid().ToString('N')).Substring(0,9)
$temp=Join-Path ([IO.Path]::GetTempPath()) "tfpro-c49-$runId"; $work=Join-Path $temp 'candidate'
$pVpc=$null;$dVpc=$null;$pSubnet=$null;$dSubnet=$null;$pAmi=$null;$dAmi=$null;$up=$false;$failure=$null
$saved=@{};foreach($n in @('AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_DEFAULT_REGION','AWS_EC2_METADATA_DISABLED','AWS_PAGER','TF_VAR_run_id','TF_VAR_primary_subnet_id','TF_VAR_dr_subnet_id','TF_VAR_primary_image_id','TF_VAR_dr_image_id','TF_VAR_localstack_endpoint')){$saved[$n]=[Environment]::GetEnvironmentVariable($n)}
try {
  Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5 | Out-Null
  $env:AWS_ACCESS_KEY_ID='test';$env:AWS_SECRET_ACCESS_KEY='test';$env:AWS_DEFAULT_REGION='us-east-1';$env:AWS_EC2_METADATA_DISABLED='true';$env:AWS_PAGER=''
  $pVpc=(Aws 'us-east-1' @('ec2','create-vpc','--cidr-block','10.149.0.0/16','--query','Vpc.VpcId','--output','text') -Quiet).Text.Trim()
  $pSubnet=(Aws 'us-east-1' @('ec2','create-subnet','--vpc-id',$pVpc,'--cidr-block','10.149.1.0/24','--availability-zone','us-east-1a','--query','Subnet.SubnetId','--output','text') -Quiet).Text.Trim()
  $dVpc=(Aws 'us-west-2' @('ec2','create-vpc','--cidr-block','10.249.0.0/16','--query','Vpc.VpcId','--output','text') -Quiet).Text.Trim()
  $dSubnet=(Aws 'us-west-2' @('ec2','create-subnet','--vpc-id',$dVpc,'--cidr-block','10.249.1.0/24','--availability-zone','us-west-2a','--query','Subnet.SubnetId','--output','text') -Quiet).Text.Trim()
  $pAmi=(Aws 'us-east-1' @('ec2','register-image','--name',"tfpro-c49-$runId-primary",'--architecture','x86_64','--root-device-name','/dev/sda1','--virtualization-type','hvm','--query','ImageId','--output','text') -Quiet).Text.Trim()
  $dAmi=(Aws 'us-west-2' @('ec2','register-image','--name',"tfpro-c49-$runId-dr",'--architecture','x86_64','--root-device-name','/dev/sda1','--virtualization-type','hvm','--query','ImageId','--output','text') -Quiet).Text.Trim()
  $env:TF_VAR_run_id=$runId;$env:TF_VAR_primary_subnet_id=$pSubnet;$env:TF_VAR_dr_subnet_id=$dSubnet;$env:TF_VAR_primary_image_id=$pAmi;$env:TF_VAR_dr_image_id=$dAmi;$env:TF_VAR_localstack_endpoint=$LocalstackEndpoint
  Copy-Clean $candidate $work; Copy-Clean (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $temp 'fixtures')
  New-Item -ItemType Directory -Force (Join-Path $work 'tests') | Out-Null
  Copy-Item (Join-Path $PSScriptRoot 'canonical.tftest.hcl') (Join-Path $work 'tests\canonical.tftest.hcl')
  Tf $work @('fmt','-check','-recursive') | Out-Null; Tf $work @('init','-backend=false','-input=false','-no-color') | Out-Null; Tf $work @('validate','-no-color') | Out-Null; ExactTests $work
  Write-Host '[unit] exact 10/10 normal Terraform 1.6 runs passed.'
  if ($UnitOnly) { Write-Host 'PASS challenge-49 UnitOnly'; return }
  Remove-Item (Join-Path $work 'tests') -Recurse -Force
  $base=@('-input=false','-no-color',"-var=run_id=$runId","-var=primary_subnet_id=$pSubnet","-var=dr_subnet_id=$dSubnet","-var=primary_image_id=$pAmi","-var=dr_image_id=$dAmi","-var=localstack_endpoint=$LocalstackEndpoint");$v1=$base+@('-var=catalog_path=../fixtures/catalog-v1.json');$v2=$base+@('-var=catalog_path=../fixtures/catalog-v2.json')
  $plan=Join-Path $work 'v1.tfplan'; Tf $work (@('plan',"-out=$plan")+$v1) | Out-Null
  $e1=@{'aws_iam_role.runtime'='create';'aws_iam_instance_profile.runtime'='create';'module.primary.aws_launch_template.replica["api@primary#01"]'='create';'module.primary.aws_instance.replica["api@primary#01"]'='create';'module.dr.aws_launch_template.replica["worker@dr#01"]'='create';'module.dr.aws_instance.replica["worker@dr#01"]'='create'}
  AssertChanges (PlanDoc $work $plan) $e1 'v1 saved plan'; Tf $work @('apply','-input=false','-no-color',$plan) | Out-Null; $up=$true
  $c1=((Tf $work @('output','-json','release_contract') -Quiet).Text | ConvertFrom-Json); $pOld=$c1.primary.instances.'api@primary#01'; $dOld=$c1.dr.instances.'worker@dr#01'
  if ($c1.primary.subnet_id -ne $pSubnet -or $c1.dr.subnet_id -ne $dSubnet) { throw 'Subnet provider routing crossed.' }
  $v1Clean = Tf $work (@('plan','-detailed-exitcode')+$v1) @(0,2) -Quiet
  if ($v1Clean.Code -ne 0) { throw "v1 not clean.`n$($v1Clean.Text)" }
  $reorder=$base+@('-var=catalog_path=../fixtures/catalog-v1-reordered.json'); if ((Tf $work (@('plan','-detailed-exitcode')+$reorder) @(0,2) -Quiet).Code -ne 0) { throw 'Reorder changed graph.' }
  $v2p=Join-Path $work 'v2.tfplan'; Tf $work (@('plan',"-out=$v2p")+$v2) | Out-Null
  $e2=@{'module.primary.aws_launch_template.replica["api@primary#01"]'='update';'module.primary.aws_instance.replica["api@primary#01"]'='delete,create';'module.dr.aws_launch_template.replica["worker@dr#02"]'='create';'module.dr.aws_instance.replica["worker@dr#02"]'='create'}
  AssertChanges (PlanDoc $work $v2p) $e2 'v2 saved plan'; Tf $work @('apply','-input=false','-no-color',$v2p) | Out-Null
  $c2=((Tf $work @('output','-json','release_contract') -Quiet).Text | ConvertFrom-Json)
  if ($c2.primary.instances.'api@primary#01' -eq $pOld -or $c2.dr.instances.'worker@dr#01' -ne $dOld -or -not $c2.dr.instances.'worker@dr#02') { throw 'v2 replacement/capacity identity failed.' }
  Aws 'us-west-2' @('ec2','create-tags','--resources',$dOld,'--tags',"Key=Name,Value=$runId-tampered") -Quiet | Out-Null
  $dp=Join-Path $work 'drift.tfplan'; Tf $work (@('plan',"-out=$dp")+$v2) | Out-Null
  AssertChanges (PlanDoc $work $dp) @{'module.dr.aws_instance.replica["worker@dr#01"]'='update'} 'tag drift'; Tf $work @('apply','-input=false','-no-color',$dp) | Out-Null
  if ((Tf $work (@('plan','-detailed-exitcode')+$v2) @(0,2) -Quiet).Code -ne 0) { throw 'Drift repair not clean.' }
  $des=Join-Path $work 'destroy.tfplan'; Tf $work (@('plan','-destroy',"-out=$des")+$v2) | Out-Null
  $ed=@{}; foreach ($a in @('aws_iam_role.runtime','aws_iam_instance_profile.runtime','module.primary.aws_launch_template.replica["api@primary#01"]','module.primary.aws_instance.replica["api@primary#01"]','module.dr.aws_launch_template.replica["worker@dr#01"]','module.dr.aws_instance.replica["worker@dr#01"]','module.dr.aws_launch_template.replica["worker@dr#02"]','module.dr.aws_instance.replica["worker@dr#02"]')) { $ed[$a]='delete' }
  AssertChanges (PlanDoc $work $des) $ed 'destroy saved plan'; Tf $work @('apply','-input=false','-no-color',$des) | Out-Null; $up=$false
  $role=Aws 'us-east-1' @('iam','get-role','--role-name',"tfpro-c49-$runId") @(0,254) -Quiet
  if ($role.Code -ne 254 -or $role.Text -notmatch 'NoSuchEntity') { throw 'IAM residue.' }
  foreach ($r in @('us-east-1','us-west-2')) { $active=(Aws $r @('ec2','describe-instances','--filters',"Name=tag:RunId,Values=$runId",'Name=instance-state-name,Values=pending,running,stopping,stopped','--query','Reservations[].Instances[].InstanceId','--output','text') -Quiet).Text.Trim(); $lts=(Aws $r @('ec2','describe-launch-templates','--filters',"Name=tag:RunId,Values=$runId",'--query','LaunchTemplates[].LaunchTemplateId','--output','text') -Quiet).Text.Trim(); if ($active -or $lts) { throw "$r managed residue remains." } }
  Aws 'us-east-1' @('ec2','deregister-image','--image-id',$pAmi) -Quiet | Out-Null;$pAmi=$null; Aws 'us-west-2' @('ec2','deregister-image','--image-id',$dAmi) -Quiet | Out-Null;$dAmi=$null
  Aws 'us-east-1' @('ec2','delete-subnet','--subnet-id',$pSubnet) -Quiet | Out-Null;$pSubnet=$null; Aws 'us-west-2' @('ec2','delete-subnet','--subnet-id',$dSubnet) -Quiet | Out-Null;$dSubnet=$null
  Aws 'us-east-1' @('ec2','delete-vpc','--vpc-id',$pVpc) -Quiet | Out-Null;$pVpc=$null; Aws 'us-west-2' @('ec2','delete-vpc','--vpc-id',$dVpc) -Quiet | Out-Null;$dVpc=$null
  Write-Host '[e2e] dual-region subnet data, LT-driven replacement, capacity, reorder, drift, saved destroy, zero residue passed.'; Write-Host 'PASS challenge-49 (difficulty 95/100, alignment A)'
} catch { $failure=$_ } finally {
  $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
  if ($up -and (Test-Path $work)) { & terraform "-chdir=$work" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" "-var=primary_subnet_id=$pSubnet" "-var=dr_subnet_id=$dSubnet" "-var=primary_image_id=$pAmi" "-var=dr_image_id=$dAmi" "-var=localstack_endpoint=$LocalstackEndpoint" '-var=catalog_path=../fixtures/catalog-v2.json' 2>$null | Out-Null }
  if ($pAmi) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 deregister-image --image-id $pAmi 2>$null | Out-Null };if ($dAmi) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 deregister-image --image-id $dAmi 2>$null | Out-Null }
  if ($pSubnet) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $pSubnet 2>$null | Out-Null };if ($dSubnet) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-subnet --subnet-id $dSubnet 2>$null | Out-Null }
  if ($pVpc) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $pVpc 2>$null | Out-Null };if ($dVpc) { & aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-vpc --vpc-id $dVpc 2>$null | Out-Null }
  foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n,$saved[$n]) }
  if (Test-Path $temp) { Remove-Item -LiteralPath $temp -Recurse -Force };$ErrorActionPreference=$old
}
if ($failure) { throw $failure }
