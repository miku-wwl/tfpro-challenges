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
      $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535) { throw "Unsafe LocalStack endpoint: $Value" }
}

function Native([string]$File, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  $lines = @(& $File @Arguments 2>&1); $code = $LASTEXITCODE
  $ErrorActionPreference = $old; $text = $lines -join "`n"
  if (-not $Quiet -and $lines.Count -gt 0) { $lines | Out-Host }
  if ($code -notin $Allowed) { throw "$File $($Arguments -join ' ') failed ($code).`n$text" }
  return [pscustomobject]@{ Code = $code; Text = $text }
}
function Tf([string]$Dir, [string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) { Native 'terraform' (@("-chdir=$Dir") + $Arguments) $Allowed -Quiet:$Quiet }
function Aws([string[]]$Arguments, [int[]]$Allowed = @(0), [switch]$Quiet) { Native 'aws.exe' (@('--endpoint-url',$LocalstackEndpoint,'--region','us-east-1') + $Arguments) $Allowed -Quiet:$Quiet }
function Copy-Clean([string]$Source,[string]$Destination) {
  New-Item -ItemType Directory -Force $Destination | Out-Null
  foreach($item in Get-ChildItem -LiteralPath $Source -Force) {
    if($item.Name -in @('.terraform','.terraform.lock.hcl','terraform.tfstate','terraform.tfstate.backup','.terraform.tfstate.lock.info') -or $item.Extension -in @('.tfplan','.tfstate')) { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force
  }
}
function Exact-Tests([string]$Dir,[int]$Expected) {
  $r=Tf $Dir @('test','-test-directory=tests','-no-color')
  if([regex]::Matches($r.Text,"(?m)^Success!\s+$Expected passed,\s+0 failed\.\s*$").Count -ne 1 -or [regex]::Matches($r.Text,'(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne $Expected) { throw "Expected exactly $Expected test runs." }
}

Assert-Endpoint $LocalstackEndpoint
$candidatePath=(Resolve-Path -LiteralPath $Candidate).Path
$files=@(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if($files.Count -eq 0 -or @($files|Where-Object Extension -ne '.tf').Count -ne 0){throw 'Candidate must contain Terraform HCL only.'}
$text=($files|ForEach-Object{Get-Content -Raw -LiteralPath $_.FullName}) -join "`n"
if($text -match '(?i)\b(mock_provider|override_data|override_resource|profile|shared_credentials_files|assume_role)\b|AKIA[0-9A-Z]{16}'){throw 'Forbidden mock or credential mechanism found.'}
$awsResources=@([regex]::Matches($text,'resource\s+"(aws_[a-z0-9_]+)"')|ForEach-Object{$_.Groups[1].Value}|Sort-Object -Unique)
$awsData=@([regex]::Matches($text,'data\s+"(aws_[a-z0-9_]+)"')|ForEach-Object{$_.Groups[1].Value}|Sort-Object -Unique)
if(($awsResources -join ',') -ne 'aws_security_group,aws_vpc_security_group_ingress_rule'){throw "AWS resources must be the official security group/ingress-rule pair; got $($awsResources -join ',')."}
if(($awsData -join ',') -ne 'aws_subnet'){throw "Only data.aws_subnet is allowed; got $($awsData -join ',')."}
if($text -notmatch 'for_each\s*=\s*local\.rules_by_key' -or $text -notmatch 'data\s+"aws_subnet"\s+"selected"' -or $text -notmatch 'id_groups' -or $text -match 'overlap_pairs|direction'){throw 'Stable ingress-only compiler or validation contract is incomplete.'}
if($text -notmatch 'resource\s+"aws_security_group"\s+"rules"[\s\S]*?precondition\s*\{'){throw 'The security group needs a blocking catalog precondition.'}
if($text -notmatch 'access_key\s*=\s*"test"' -or $text -notmatch 'secret_key\s*=\s*"test"' -or $text -notmatch 'skip_credentials_validation\s*=\s*true' -or $text -notmatch 'skip_metadata_api_check\s*=\s*true' -or $text -notmatch 'skip_requesting_account_id\s*=\s*true'){throw 'Safe LocalStack provider contract is incomplete.'}

$runId=([Guid]::NewGuid().ToString('N')).Substring(0,10); $temp=Join-Path ([IO.Path]::GetTempPath()) "tfpro-c37-$runId"; $work=Join-Path $temp 'candidate'
$vpcId=$null; $subnetId=$null; $sgId=$null; $failure=$null
$oldAccess=$env:AWS_ACCESS_KEY_ID; $oldSecret=$env:AWS_SECRET_ACCESS_KEY; $oldRegion=$env:AWS_DEFAULT_REGION; $oldSubnet=$env:TF_VAR_subnet_id
$env:AWS_ACCESS_KEY_ID='test';$env:AWS_SECRET_ACCESS_KEY='test';$env:AWS_DEFAULT_REGION='us-east-1'
try {
  try{Invoke-WebRequest -UseBasicParsing -Uri "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5|Out-Null}catch{throw 'LocalStack is unavailable.'}
  $vpcId=(Aws @('ec2','create-vpc','--cidr-block','10.137.0.0/16','--tag-specifications',"ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]",'--query','Vpc.VpcId','--output','text') -Quiet).Text.Trim()
  $subnetId=(Aws @('ec2','create-subnet','--vpc-id',$vpcId,'--cidr-block','10.137.1.0/24','--availability-zone','us-east-1a','--tag-specifications',"ResourceType=subnet,Tags=[{Key=RunId,Value=$runId}]",'--query','Subnet.SubnetId','--output','text') -Quiet).Text.Trim()
  $env:TF_VAR_subnet_id=$subnetId
  Copy-Clean $candidatePath $work; Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\fixtures') -Destination (Join-Path $temp 'fixtures') -Recurse -Force
  New-Item -ItemType Directory -Force (Join-Path $work 'tests')|Out-Null; Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'canonical.tftest.hcl') -Destination (Join-Path $work 'tests\canonical.tftest.hcl')
  Tf $work @('fmt','-check','-recursive')|Out-Null; Tf $work @('init','-backend=false','-input=false','-no-color')|Out-Null; Tf $work @('validate','-no-color')|Out-Null; Exact-Tests $work 12
  if($UnitOnly){Write-Host 'PASS: Challenge 37 exact 12/12 TF1.6 tests with real data.aws_subnet.';return}
  Remove-Item -LiteralPath (Join-Path $work 'tests') -Recurse -Force
  $common=@('-input=false','-no-color',"-var=subnet_id=$subnetId","-var=run_id=$runId",'-var=name_prefix=tfpro-c37','-var=rules_csv_path=../fixtures/rules.csv')
  $plan=Join-Path $work 'reviewed.tfplan'; Tf $work (@('plan',"-out=$plan")+$common)|Out-Null
  $json=(Tf $work @('show','-json',$plan) -Quiet).Text|ConvertFrom-Json
  $creates=@($json.resource_changes|Where-Object{@($_.change.actions)-join ',' -eq 'create'})
  if($creates.Count -ne 4){throw "Expected exactly 4 creates, got $($creates.Count)."}
  Tf $work @('apply','-input=false','-no-color',$plan)|Out-Null
  $contract=((Tf $work @('output','-json','security_contract') -Quiet).Text|ConvertFrom-Json); $sgId=$contract.security_group_id
  if($contract.subnet_id -ne $subnetId -or $contract.vpc_id -ne $vpcId){throw 'Subnet/VPC data-source contract mismatch.'}
  $remote=(Aws @('ec2','describe-security-group-rules','--filters',"Name=group-id,Values=$sgId",'--output','json') -Quiet).Text|ConvertFrom-Json
  $managed=@($remote.SecurityGroupRules|Where-Object{$_.Description -in @('application TLS','administration','service DNS')})
  if($managed.Count -ne 3){throw "Expected three real ingress rules, got $($managed.Count)."}
  $reorder=Tf $work (@('plan','-detailed-exitcode')+($common|Where-Object{$_ -notlike '-var=rules_csv_path=*'})+@('-var=rules_csv_path=../fixtures/rules-reordered.csv')) @(0,2) -Quiet
  if($reorder.Code -ne 0){throw "CSV reorder changed the graph.`n$($reorder.Text)"}
  $victim=@($managed|Where-Object Description -eq 'application TLS')[0]
  Aws @('ec2','revoke-security-group-ingress','--group-id',$sgId,'--security-group-rule-ids',$victim.SecurityGroupRuleId)|Out-Null
  $drift=Join-Path $work 'drift.tfplan'; $dr=Tf $work (@('plan','-detailed-exitcode',"-out=$drift")+$common) @(0,2) -Quiet
  if($dr.Code -ne 2){throw 'Remote rule deletion was not detected.'}
  $dj=(Tf $work @('show','-json',$drift) -Quiet).Text|ConvertFrom-Json
  $changes=@($dj.resource_changes|Where-Object{$_.address -like 'aws_vpc_security_group_ingress_rule.rule*' -and (@($_.change.actions)-join ',') -eq 'create'})
  if($changes.Count -ne 1){throw 'Drift plan must recreate exactly one rule.'}
  Tf $work @('apply','-input=false','-no-color',$drift)|Out-Null
  $clean=Tf $work (@('plan','-detailed-exitcode')+$common) @(0,2) -Quiet; if($clean.Code -ne 0){throw 'Post-repair plan is not clean.'}
  Tf $work (@('destroy','-auto-approve')+$common)|Out-Null; $sgId=$null
  $left=(Aws @('ec2','describe-security-groups','--filters',"Name=tag:RunId,Values=$runId",'--query','SecurityGroups[].GroupId','--output','text') -Quiet).Text
  if(-not [string]::IsNullOrWhiteSpace($left)){throw 'Managed security-group residue remains.'}
  Write-Host 'PASS: Challenge 37 TF1.6 tests + official ingress rules + saved plan + reorder/drift repair + zero managed residue.'
}catch{$failure=$_}finally{
  $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
  if(Test-Path $work){& terraform "-chdir=$work" destroy -auto-approve -input=false -no-color "-var=subnet_id=$subnetId" "-var=run_id=$runId" '-var=name_prefix=tfpro-c37' '-var=rules_csv_path=../fixtures/rules.csv' 2>$null|Out-Null}
  if($sgId){& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-security-group --group-id $sgId 2>$null|Out-Null}
  if($subnetId){& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $subnetId 2>$null|Out-Null}
  if($vpcId){& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $vpcId 2>$null|Out-Null}
  $env:AWS_ACCESS_KEY_ID=$oldAccess;$env:AWS_SECRET_ACCESS_KEY=$oldSecret;$env:AWS_DEFAULT_REGION=$oldRegion;$env:TF_VAR_subnet_id=$oldSubnet
  if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force};$ErrorActionPreference=$old
}
if($failure){throw $failure}
