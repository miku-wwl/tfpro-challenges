[CmdletBinding()]
param(
  [string]$Candidate = '',
  [string]$LocalstackEndpoint = 'http://localhost:4566',
  [switch]$UnitOnly
)

if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Join-Path $PSScriptRoot '..\starter' }

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

function Native([string]$File,[string[]]$Arguments,[int[]]$Allowed=@(0),[switch]$Quiet) {
  $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
  $lines=@(& $File @Arguments 2>&1 | ForEach-Object{"$_"}); $code=$LASTEXITCODE
  $ErrorActionPreference=$old; $joined=$lines -join "`n"
  if(-not $Quiet -and $lines.Count -gt 0){$lines|Out-Host}
  if($code -notin $Allowed){throw "$File $($Arguments -join ' ') failed ($code).`n$joined"}
  [pscustomobject]@{Code=$code;Text=$joined}
}
function Tf([string]$Dir,[string[]]$Arguments,[int[]]$Allowed=@(0),[switch]$Quiet){Native 'terraform' (@("-chdir=$Dir")+$Arguments) $Allowed -Quiet:$Quiet}
function Aws([string]$Region,[string[]]$Arguments,[int[]]$Allowed=@(0),[switch]$Quiet){Native 'aws.exe' (@('--endpoint-url',$LocalstackEndpoint,'--region',$Region)+$Arguments) $Allowed -Quiet:$Quiet}
function Copy-Clean([string]$Source,[string]$Destination){
  New-Item -ItemType Directory -Force $Destination|Out-Null
  foreach($item in Get-ChildItem -LiteralPath $Source -Force){
    if($item.Name -in @('.terraform','.terraform.lock.hcl','terraform.tfstate','terraform.tfstate.backup','.terraform.tfstate.lock.info') -or $item.Extension -in @('.tfplan','.tfstate')){continue}
    if($item.PSIsContainer){Copy-Clean $item.FullName (Join-Path $Destination $item.Name)}else{Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Destination $item.Name) -Force}
  }
}
function Exact-Tests([string]$Dir,[int]$Expected){
  $r=Tf $Dir @('test','-test-directory=tests','-no-color')
  if([regex]::Matches($r.Text,"(?m)^Success!\s+$Expected passed,\s+0 failed\.\s*$").Count -ne 1 -or
     [regex]::Matches($r.Text,'(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne $Expected){throw "Expected exactly $Expected Terraform 1.6 runs."}
}
function Plan-Json([string]$Dir,[string]$Plan){((Tf $Dir @('show','-json',$Plan) -Quiet).Text|ConvertFrom-Json)}
function Change-Map($Document){
  $map=@{}
  foreach($change in @($Document.resource_changes|Where-Object{[string]$_.address -notlike 'data.*'})){
    $actions=@($change.change.actions)-join ','
    if($actions -ne 'no-op'){$map[[string]$change.address]=$actions}
  }
  $map
}
function Assert-Changes($Document,[hashtable]$Expected,[string]$Label){
  $actual=Change-Map $Document
  if($actual.Count -ne $Expected.Count){throw "$Label expected $($Expected.Count) changes, got $($actual.Count): $($actual.Keys -join ', ')"}
  foreach($key in $Expected.Keys){if(-not $actual.ContainsKey($key) -or $actual[$key] -ne $Expected[$key]){throw "$Label expected $key=$($Expected[$key]); got $($actual[$key])."}}
}

Assert-Endpoint $LocalstackEndpoint
$terraformVersion=((Native 'terraform' @('version','-json') -Quiet).Text|ConvertFrom-Json).terraform_version
if($terraformVersion -ne '1.6.6'){throw "Terraform 1.6.6 is required; active version is $terraformVersion."}
$candidatePath=(Resolve-Path -LiteralPath $Candidate).Path
$files=@(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if($files.Count -eq 0 -or @($files|Where-Object Extension -ne '.tf').Count -ne 0){throw 'Candidate must contain Terraform HCL only.'}
$text=($files|ForEach-Object{Get-Content -Raw -LiteralPath $_.FullName})-join "`n"
if($text -match '(?i)\b(TODO|terraform_data|mock_provider|override_data|override_resource|aws_sns_|aws_vpc|aws_subnets)\b|ignore_changes'){throw 'Forbidden starter, mock, synthetic, SNS, or VPC discovery construct found.'}
if($text -notmatch 'required_version\s*=\s*"~> 1\.6"' -or $text -notmatch 'version\s*=\s*"~> 5\.100"'){throw 'Exact Terraform/provider constraints are required.'}
$resources=@([regex]::Matches($text,'resource\s+"(aws_[a-z0-9_]+)"')|ForEach-Object{$_.Groups[1].Value}|Sort-Object -Unique)
$data=@([regex]::Matches($text,'data\s+"(aws_[a-z0-9_]+)"')|ForEach-Object{$_.Groups[1].Value}|Sort-Object -Unique)
if(($resources-join ',') -ne 'aws_iam_instance_profile,aws_iam_role,aws_instance'){throw "Unexpected resources: $($resources-join ',')"}
if(($data-join ',') -ne 'aws_ami,aws_caller_identity,aws_iam_policy_document,aws_subnet'){throw "Unexpected data sources: $($data-join ',')"}
if([regex]::Matches($text,'provider\s+"aws"\s*\{').Count -ne 2 -or $text -notmatch 'alias\s*=\s*"audit"'){throw 'Exactly default and aws.audit configurations are required.'}
$rootMain=Get-Content -Raw -LiteralPath (Join-Path $candidatePath 'main.tf')
if($rootMain -notmatch 'module\s+"primary"[\s\S]*?providers\s*=\s*\{\s*aws\s*=\s*aws\s*\}' -or
   $rootMain -notmatch 'module\s+"audit"[\s\S]*?providers\s*=\s*\{\s*aws\s*=\s*aws\.audit\s*\}'){throw 'Both module provider routes must be explicit.'}
foreach($token in @('data "aws_ami"','data "aws_subnet"','data "aws_iam_policy_document"','routes_by_name','precondition')){if($text -notmatch [regex]::Escape($token)){throw "Missing required contract: $token"}}
$testText=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl')
if($testText -match '(?i)mock_provider|override_' -or [regex]::Matches($testText,'(?m)^run\s+"').Count -ne 8){throw 'Canonical tests must be exactly 8 normal Terraform 1.6 runs without mocks/overrides.'}

$runId='c47-'+([Guid]::NewGuid().ToString('N')).Substring(0,10)
$temp=Join-Path ([IO.Path]::GetTempPath()) "tfpro-c47-$runId"; $work=Join-Path $temp 'candidate'
$primaryVpc=$null;$auditVpc=$null;$primarySubnet=$null;$auditSubnet=$null;$primaryAmi=$null;$auditAmi=$null;$initialized=$false;$failure=$null
$savedEnv=@{};foreach($name in @('AWS_ACCESS_KEY_ID','AWS_SECRET_ACCESS_KEY','AWS_DEFAULT_REGION','AWS_EC2_METADATA_DISABLED','AWS_PAGER','TF_VAR_run_id','TF_VAR_primary_subnet_id','TF_VAR_audit_subnet_id','TF_VAR_localstack_endpoint')){$savedEnv[$name]=[Environment]::GetEnvironmentVariable($name)}
try{
  try{Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5|Out-Null}catch{throw 'LocalStack is unavailable.'}
  $env:AWS_ACCESS_KEY_ID='test';$env:AWS_SECRET_ACCESS_KEY='test';$env:AWS_DEFAULT_REGION='us-east-1';$env:AWS_EC2_METADATA_DISABLED='true';$env:AWS_PAGER=''
  $primaryVpc=(Aws 'us-east-1' @('ec2','create-vpc','--cidr-block','10.147.0.0/16','--tag-specifications',"ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]",'--query','Vpc.VpcId','--output','text') -Quiet).Text.Trim()
  $primarySubnet=(Aws 'us-east-1' @('ec2','create-subnet','--vpc-id',$primaryVpc,'--cidr-block','10.147.1.0/24','--availability-zone','us-east-1a','--tag-specifications',"ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]",'--query','Subnet.SubnetId','--output','text') -Quiet).Text.Trim()
  $auditVpc=(Aws 'us-west-2' @('ec2','create-vpc','--cidr-block','10.247.0.0/16','--tag-specifications',"ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]",'--query','Vpc.VpcId','--output','text') -Quiet).Text.Trim()
  $auditSubnet=(Aws 'us-west-2' @('ec2','create-subnet','--vpc-id',$auditVpc,'--cidr-block','10.247.1.0/24','--availability-zone','us-west-2a','--tag-specifications',"ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]",'--query','Subnet.SubnetId','--output','text') -Quiet).Text.Trim()
  $primaryAmi=(Aws 'us-east-1' @('ec2','register-image','--name',"tfpro-c47-$runId-primary",'--architecture','x86_64','--root-device-name','/dev/sda1','--virtualization-type','hvm','--query','ImageId','--output','text') -Quiet).Text.Trim()
  $auditAmi=(Aws 'us-west-2' @('ec2','register-image','--name',"tfpro-c47-$runId-audit",'--architecture','x86_64','--root-device-name','/dev/sda1','--virtualization-type','hvm','--query','ImageId','--output','text') -Quiet).Text.Trim()
  $env:TF_VAR_run_id=$runId;$env:TF_VAR_primary_subnet_id=$primarySubnet;$env:TF_VAR_audit_subnet_id=$auditSubnet;$env:TF_VAR_localstack_endpoint=$LocalstackEndpoint
  Copy-Clean $candidatePath $work;Copy-Clean (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $temp 'fixtures')
  New-Item -ItemType Directory -Force (Join-Path $work 'tests')|Out-Null;Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $work 'tests\canonical.tftest.hcl')
  Tf $work @('fmt','-check','-recursive')|Out-Null;Tf $work @('init','-backend=false','-input=false','-no-color')|Out-Null;$initialized=$true;Tf $work @('validate','-no-color')|Out-Null;Exact-Tests $work 8
  Write-Host '[unit] fmt/init/validate and exact 8/8 normal Terraform 1.6 runs passed.'
  if($UnitOnly){Write-Host 'PASS challenge-47 UnitOnly';return}
  Remove-Item -LiteralPath (Join-Path $work 'tests') -Recurse -Force
  $common=@('-input=false','-no-color',"-var=run_id=$runId","-var=primary_subnet_id=$primarySubnet","-var=audit_subnet_id=$auditSubnet","-var=localstack_endpoint=$LocalstackEndpoint",'-var=catalog_path=../fixtures/routes.json')
  $plan=Join-Path $work 'reviewed.tfplan';Tf $work (@('plan',"-out=$plan")+$common)|Out-Null;$doc=Plan-Json $work $plan
  $initial=@{'aws_iam_role.workload'='create';'aws_iam_instance_profile.workload'='create';'module.primary.aws_instance.node'='create';'module.audit.aws_instance.node'='create'}
  Assert-Changes $doc $initial 'Initial saved plan'
  foreach($address in @('module.primary.aws_instance.node','module.audit.aws_instance.node')){$change=@($doc.resource_changes|Where-Object address -eq $address)[0];if(-not $change.change.after.subnet_id -or -not $change.change.after.ami){throw "$address saved-plan contract is incomplete."}}
  $hash=(Get-FileHash -LiteralPath $plan -Algorithm SHA256).Hash;if((Get-FileHash -LiteralPath $plan -Algorithm SHA256).Hash -ne $hash){throw 'Saved plan changed after audit.'}
  Tf $work @('apply','-input=false','-no-color',$plan)|Out-Null
  $contract=((Tf $work @('output','-json','routing_contract') -Quiet).Text|ConvertFrom-Json)
  if($contract.primary.ami_id -ne $primaryAmi -or $contract.audit.ami_id -ne $auditAmi -or $contract.primary.subnet_id -ne $primarySubnet -or $contract.audit.subnet_id -ne $auditSubnet){throw 'Provider-routed AMI/subnet contract is crossed.'}
  Aws 'us-east-1' @('iam','get-role','--role-name',$contract.role_name) -Quiet|Out-Null
  foreach($entry in @(@('us-east-1',$contract.primary,'primary',$primaryAmi,$primarySubnet),@('us-west-2',$contract.audit,'audit',$auditAmi,$auditSubnet))){
    $instance=((Aws $entry[0] @('ec2','describe-instances','--instance-ids',$entry[1].instance_id,'--query','Reservations[0].Instances[0]','--output','json') -Quiet).Text|ConvertFrom-Json);$tags=@{};foreach($tag in $instance.Tags){$tags[$tag.Key]=$tag.Value}
    if($instance.ImageId -ne $entry[3] -or $instance.SubnetId -ne $entry[4] -or $tags.Route -ne $entry[2] -or $tags.Region -ne $entry[0] -or $tags.RunId -ne $runId -or $instance.IamInstanceProfile.Arn -notmatch [regex]::Escape($contract.instance_profile)){throw "$($entry[2]) real EC2 routing contract failed."}
  }
  $clean=Tf $work (@('plan','-detailed-exitcode')+$common) @(0,2) -Quiet;if($clean.Code -ne 0){throw 'Post-apply plan is not clean.'}
  $reorder=Tf $work (@('plan','-detailed-exitcode')+($common|Where-Object{$_ -notlike '-var=catalog_path=*'})+@('-var=catalog_path=../fixtures/routes-reordered.json')) @(0,2) -Quiet;if($reorder.Code -ne 0){throw 'Route catalog reorder changed the graph.'}
  $same=Tf $work (@('plan')+($common|Where-Object{$_ -notlike '-var=audit_subnet_id=*'})+@("-var=audit_subnet_id=$primarySubnet")) @(0,1) -Quiet;if($same.Code -ne 1 -or $same.Text -notmatch 'distinct injected subnets'){throw 'Identical subnet guard did not block the plan.'}
  Aws 'us-west-2' @('ec2','terminate-instances','--instance-ids',$contract.audit.instance_id) -Quiet|Out-Null
  Aws 'us-west-2' @('ec2','wait','instance-terminated','--instance-ids',$contract.audit.instance_id) -Quiet|Out-Null
  $driftPlan=Join-Path $work 'drift.tfplan';$drift=Tf $work (@('plan','-detailed-exitcode',"-out=$driftPlan")+$common) @(0,2) -Quiet;if($drift.Code -ne 2){throw 'Audit instance deletion was not detected.'};$driftDoc=Plan-Json $work $driftPlan;Assert-Changes $driftDoc @{'module.audit.aws_instance.node'='create'} 'Drift saved plan';Tf $work @('apply','-input=false','-no-color',$driftPlan)|Out-Null
  $final=Tf $work (@('plan','-detailed-exitcode')+$common) @(0,2) -Quiet;if($final.Code -ne 0){throw 'Drift repair is not clean.'}
  $destroyPlan=Join-Path $work 'destroy.tfplan';Tf $work (@('plan','-destroy',"-out=$destroyPlan")+$common)|Out-Null;$destroyDoc=Plan-Json $work $destroyPlan;Assert-Changes $destroyDoc @{'aws_iam_role.workload'='delete';'aws_iam_instance_profile.workload'='delete';'module.primary.aws_instance.node'='delete';'module.audit.aws_instance.node'='delete'} 'Destroy saved plan';Tf $work @('apply','-input=false','-no-color',$destroyPlan)|Out-Null;$initialized=$false
  $role=Aws 'us-east-1' @('iam','get-role','--role-name',"tfpro-c47-$runId") @(0,254) -Quiet;if($role.Code -ne 254 -or $role.Text -notmatch 'NoSuchEntity'){throw 'IAM role residue or imprecise absence response.'}
  foreach($region in @('us-east-1','us-west-2')){$active=(Aws $region @('ec2','describe-instances','--filters',"Name=tag:RunId,Values=$runId",'Name=instance-state-name,Values=pending,running,stopping,stopped','--query','Reservations[].Instances[].InstanceId','--output','text') -Quiet).Text.Trim();if($active){throw "$region active EC2 residue remains: $active"}}
  Aws 'us-east-1' @('ec2','deregister-image','--image-id',$primaryAmi) -Quiet|Out-Null;$primaryAmi=$null;Aws 'us-west-2' @('ec2','deregister-image','--image-id',$auditAmi) -Quiet|Out-Null;$auditAmi=$null
  Aws 'us-east-1' @('ec2','delete-subnet','--subnet-id',$primarySubnet) -Quiet|Out-Null;$primarySubnet=$null;Aws 'us-west-2' @('ec2','delete-subnet','--subnet-id',$auditSubnet) -Quiet|Out-Null;$auditSubnet=$null
  Aws 'us-east-1' @('ec2','delete-vpc','--vpc-id',$primaryVpc) -Quiet|Out-Null;$primaryVpc=$null;Aws 'us-west-2' @('ec2','delete-vpc','--vpc-id',$auditVpc) -Quiet|Out-Null;$auditVpc=$null
  Write-Host '[e2e] audited saved plan, real dual-region AMI/subnet routing, reorder, drift repair, saved destroy, and zero managed residue passed.'
  Write-Host 'PASS challenge-47 (difficulty 95/100, alignment A)'
}catch{$failure=$_}finally{
  $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
  if($initialized -and (Test-Path $work)){& terraform "-chdir=$work" destroy -auto-approve -input=false -no-color 2>$null|Out-Null}
  if($primaryAmi){& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 deregister-image --image-id $primaryAmi 2>$null|Out-Null};if($auditAmi){& aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 deregister-image --image-id $auditAmi 2>$null|Out-Null}
  if($primarySubnet){& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $primarySubnet 2>$null|Out-Null};if($auditSubnet){& aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-subnet --subnet-id $auditSubnet 2>$null|Out-Null}
  if($primaryVpc){& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $primaryVpc 2>$null|Out-Null};if($auditVpc){& aws.exe --endpoint-url $LocalstackEndpoint --region us-west-2 ec2 delete-vpc --vpc-id $auditVpc 2>$null|Out-Null}
  foreach($name in $savedEnv.Keys){[Environment]::SetEnvironmentVariable($name,$savedEnv[$name])}
  if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force};$ErrorActionPreference=$old
}
if($failure){throw $failure}
