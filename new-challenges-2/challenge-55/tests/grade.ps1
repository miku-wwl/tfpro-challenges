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
  try { $uri = [Uri]$Value } catch { throw "Unsafe LocalStack endpoint: $Value" }
  if (-not $uri.IsAbsoluteUri -or $uri.DnsSafeHost -notin @('localhost','127.0.0.1','::1') -or $uri.UserInfo -ne '' -or $uri.AbsolutePath -ne '/' -or $uri.Query -ne '' -or $uri.Fragment -ne '' -or $uri.Port -lt 1 -or $uri.Port -gt 65535) { throw "Unsafe LocalStack endpoint: $Value" }
}
function Native([string]$File,[string[]]$Arguments,[int[]]$Allowed=@(0),[switch]$Quiet) {
  $old=$ErrorActionPreference; $ErrorActionPreference='Continue'; $lines=@(& $File @Arguments 2>&1); $code=$LASTEXITCODE; $ErrorActionPreference=$old
  $text=$lines -join "`n"; if(-not $Quiet -and $lines.Count){$lines|Out-Host}; if($code -notin $Allowed){throw "$File failed ($code): $($Arguments -join ' ')`n$text"}; [pscustomobject]@{Code=$code;Text=$text}
}
function Tf([string]$Dir,[string[]]$Arguments,[int[]]$Allowed=@(0),[switch]$Quiet){Native 'terraform' (@("-chdir=$Dir")+$Arguments) $Allowed -Quiet:$Quiet}
function Aws([string[]]$Arguments,[int[]]$Allowed=@(0),[switch]$Quiet){Native 'aws.exe' (@('--endpoint-url',$LocalstackEndpoint,'--region','us-east-1')+$Arguments) $Allowed -Quiet:$Quiet}
function Copy-Clean([string]$Source,[string]$Destination){New-Item -ItemType Directory -Force $Destination|Out-Null; foreach($item in Get-ChildItem -LiteralPath $Source -Force){if($item.Name -in @('.terraform','.terraform.lock.hcl','terraform.tfstate','terraform.tfstate.backup') -or $item.Extension -in @('.tfplan','.tfstate')){continue}; Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force}}
function Plan-Json([string]$Dir,[string]$Plan){(Tf $Dir @('show','-json',$Plan) -Quiet).Text|ConvertFrom-Json}
function Action-Map($Json){$m=@{};foreach($c in @($Json.resource_changes)){$a=@($c.change.actions)-join ',';if($a -notin @('no-op','read')){$m[$c.address]=$a}};$m}
function Assert-Map($Actual,[hashtable]$Expected,[string]$Label){if($Actual.Count -ne $Expected.Count){throw "$Label action count mismatch: $($Actual.Keys -join ', ')"};foreach($k in $Expected.Keys){if(-not $Actual.ContainsKey($k) -or $Actual[$k] -ne $Expected[$k]){throw "$Label action mismatch at ${k}: $($Actual[$k])"}}}
function Tags($List){$m=@{};foreach($t in @($List)){$m[$t.Key]=$t.Value};$m}

Assert-Endpoint $LocalstackEndpoint
$candidatePath=(Resolve-Path -LiteralPath $Candidate).Path
$files=@(Get-ChildItem -LiteralPath $candidatePath -Recurse -File)
if(-not $files.Count -or @($files|Where-Object Extension -ne '.tf').Count){throw 'Candidate must contain HCL only.'}
$text=($files|ForEach-Object{Get-Content -Raw -LiteralPath $_.FullName})-join "`n"
if($text -match '(?i)\b(terraform_data|mock_provider|override_data|override_resource|aws_autoscaling_group|desired_capacity|min_size|max_size|ignore_changes|shared_credentials|assume_role)\b|AKIA[0-9A-Z]{16}'){throw 'Forbidden workaround, ASG placeholder, mock, or credential mechanism found.'}
$types=@([regex]::Matches($text,'resource\s+"(aws_[a-z0-9_]+)"')|ForEach-Object{$_.Groups[1].Value}|Sort-Object -Unique)
if(($types -join ',') -ne 'aws_instance,aws_launch_template,aws_security_group'){throw "Unexpected managed AWS types: $($types -join ',')"}
if($text -match 'resource\s+"aws_(?:vpc|subnet)"'){throw 'Network must remain external.'}
foreach($token in @('data "aws_subnet" "target"','data "aws_ami" "release"','for_each = local.services','for_each = local.nodes','user_data_replace_on_change = true','create_before_destroy = true','LaunchTemplateId')){if($text -notmatch [regex]::Escape($token)){throw "Missing fleet contract token: $token"}}
if($text -notmatch 'access_key\s*=\s*"test"' -or $text -notmatch 'secret_key\s*=\s*"test"' -or $text -notmatch 'skip_credentials_validation\s*=\s*true' -or $text -notmatch 'skip_metadata_api_check\s*=\s*true' -or $text -notmatch 'skip_requesting_account_id\s*=\s*true'){throw 'Safe LocalStack provider contract missing.'}
$version=(Native 'terraform' @('version','-json') -Quiet).Text|ConvertFrom-Json
if($version.terraform_version -ne '1.6.6'){throw "Terraform 1.6.6 required, found $($version.terraform_version)."}

$runId='c55'+([Guid]::NewGuid().ToString('N')).Substring(0,8); $temp=Join-Path ([IO.Path]::GetTempPath()) "tfpro-c55-$runId"; $work=Join-Path $temp 'candidate'; $vpc=$null;$subnet=$null;$failure=$null
$oldA=$env:AWS_ACCESS_KEY_ID;$oldS=$env:AWS_SECRET_ACCESS_KEY;$oldR=$env:AWS_DEFAULT_REGION
$env:AWS_ACCESS_KEY_ID='test';$env:AWS_SECRET_ACCESS_KEY='test';$env:AWS_DEFAULT_REGION='us-east-1'
try {
  try{Invoke-WebRequest -UseBasicParsing "$($LocalstackEndpoint.TrimEnd('/'))/_localstack/health" -TimeoutSec 5|Out-Null}catch{throw 'LocalStack is unavailable.'}
  $vpc=((Aws @('ec2','create-vpc','--cidr-block','10.155.0.0/24','--tag-specifications',"ResourceType=vpc,Tags=[{Key=RunId,Value=$runId}]",'--query','Vpc.VpcId','--output','text') -Quiet).Text).Trim()
  $subnet=((Aws @('ec2','create-subnet','--vpc-id',$vpc,'--cidr-block','10.155.0.0/28','--query','Subnet.SubnetId','--output','text') -Quiet).Text).Trim()
  Copy-Clean $candidatePath $work; Copy-Item (Join-Path $PSScriptRoot '..\fixtures') (Join-Path $work 'fixtures') -Recurse -Force; New-Item -ItemType Directory -Force (Join-Path $work 'tests')|Out-Null; Copy-Item (Join-Path $PSScriptRoot 'canonical.tftest.hcl') (Join-Path $work 'tests\canonical.tftest.hcl')
  $common=@('-input=false','-no-color',"-var=run_id=$runId","-var=subnet_id=$subnet")
  Tf $work @('fmt','-check','-recursive')|Out-Null; Tf $work @('init','-backend=false','-input=false','-no-color')|Out-Null; Tf $work @('validate','-no-color')|Out-Null
  $tests=Tf $work @('test','-test-directory=tests','-no-color',"-var=run_id=$runId","-var=subnet_id=$subnet")
  if([regex]::Matches($tests.Text,'(?m)^\s*run\s+"[^"]+"\.\.\.\s+pass\s*$').Count -ne 8 -or $tests.Text -notmatch '(?m)^Success!\s+8 passed,\s+0 failed\.\s*$'){throw 'Expected exact 8/8 canonical tests.'}
  if($UnitOnly){Write-Host 'PASS: Challenge 55 exact 8/8 Terraform 1.6.6 tests.';return}

  $v1=Join-Path $work 'v1.tfplan'; Tf $work (@('plan',"-out=$v1",'-var=catalog_path=fixtures/catalog-v1.json')+$common)|Out-Null
  Assert-Map (Action-Map (Plan-Json $work $v1)) @{
    'aws_security_group.fleet'='create';'aws_launch_template.release["api"]'='create';'aws_launch_template.release["worker"]'='create';'aws_instance.node["api-a"]'='create';'aws_instance.node["worker-a"]'='create'
  } 'v1'; Tf $work @('apply','-input=false','-no-color',$v1)|Out-Null
  $v1Contract=(Tf $work @('output','-json','fleet_contract') -Quiet).Text|ConvertFrom-Json; $v1Ids=$v1Contract.instances
  foreach($node in @('api-a','worker-a')){$i=(Aws @('ec2','describe-instances','--instance-ids',$v1Contract.instances.$node.id,'--query','Reservations[0].Instances[0]','--output','json') -Quiet).Text|ConvertFrom-Json;$tags=Tags $i.Tags;if($i.SubnetId -ne $subnet -or $tags.Node -ne $node -or $tags.ReleaseVersion -ne '2026.07.1' -or $tags.LaunchTemplateId -ne $v1Contract.instances.$node.launch_template_id){throw "$node v1 EC2 contract mismatch."}}
  $reorder=Tf $work (@('plan','-detailed-exitcode','-var=catalog_path=fixtures/catalog-v1-reordered.json')+$common) @(0,2) -Quiet;if($reorder.Code -ne 0){throw 'Catalog reorder changed the graph.'}

  $v2=Join-Path $work 'v2.tfplan';Tf $work (@('plan',"-out=$v2",'-var=catalog_path=fixtures/catalog-v2.json')+$common)|Out-Null
  Assert-Map (Action-Map (Plan-Json $work $v2)) @{
    'aws_launch_template.release["api"]'='update';'aws_launch_template.release["worker"]'='update';'aws_instance.node["api-a"]'='create,delete';'aws_instance.node["worker-a"]'='create,delete'
  } 'v2 rollout';Tf $work @('apply','-input=false','-no-color',$v2)|Out-Null
  $v2Contract=(Tf $work @('output','-json','fleet_contract') -Quiet).Text|ConvertFrom-Json;foreach($node in @('api-a','worker-a')){if($v2Contract.instances.$node.id -eq $v1Ids.$node.id){throw "$node did not roll."}}

  $outPlan=Join-Path $work 'scale-out.tfplan';Tf $work (@('plan',"-out=$outPlan",'-var=catalog_path=fixtures/catalog-v2-scale-out.json')+$common)|Out-Null;Assert-Map (Action-Map (Plan-Json $work $outPlan)) @{'aws_instance.node["api-b"]'='create'} 'scale-out';Tf $work @('apply','-input=false','-no-color',$outPlan)|Out-Null
  $inPlan=Join-Path $work 'scale-in.tfplan';Tf $work (@('plan',"-out=$inPlan",'-var=catalog_path=fixtures/catalog-v2.json')+$common)|Out-Null;Assert-Map (Action-Map (Plan-Json $work $inPlan)) @{'aws_instance.node["api-b"]'='delete'} 'scale-in';Tf $work @('apply','-input=false','-no-color',$inPlan)|Out-Null

  Aws @('ec2','create-tags','--resources',$v2Contract.instances.'api-a'.id,'--tags','Key=Name,Value=tampered')|Out-Null
  $driftPlan=Join-Path $work 'drift.tfplan';$drift=Tf $work (@('plan','-detailed-exitcode',"-out=$driftPlan",'-var=catalog_path=fixtures/catalog-v2.json')+$common) @(0,2) -Quiet;if($drift.Code -ne 2){throw 'Tag drift was not detected.'};Assert-Map (Action-Map (Plan-Json $work $driftPlan)) @{'aws_instance.node["api-a"]'='update'} 'drift';Tf $work @('apply','-input=false','-no-color',$driftPlan)|Out-Null
  $clean=Tf $work (@('plan','-detailed-exitcode','-var=catalog_path=fixtures/catalog-v2.json')+$common) @(0,2) -Quiet;if($clean.Code -ne 0){throw 'Final plan is not clean.'}
  Tf $work (@('destroy','-auto-approve','-input=false','-no-color','-var=catalog_path=fixtures/catalog-v2.json')+$common)|Out-Null
  $active=(Aws @('ec2','describe-instances','--filters',"Name=tag:RunId,Values=$runId",'Name=instance-state-name,Values=pending,running,stopping,stopped','--query','Reservations[].Instances[].InstanceId','--output','text') -Quiet).Text;$sgs=(Aws @('ec2','describe-security-groups','--filters',"Name=tag:RunId,Values=$runId",'--query','SecurityGroups[].GroupId','--output','text') -Quiet).Text;$lts=(Aws @('ec2','describe-launch-templates','--query','LaunchTemplates[].LaunchTemplateName','--output','text') -Quiet).Text;if(-not [string]::IsNullOrWhiteSpace($active) -or -not [string]::IsNullOrWhiteSpace($sgs) -or $lts -match [regex]::Escape($runId)){throw 'Run-scoped EC2 residue remains.'}
  Write-Host 'PASS: Challenge 55 TF1.6.6 + strict rollout/scale/drift action maps + real LocalStack + zero residue.'
} catch {$failure=$_} finally {
  $old=$ErrorActionPreference;$ErrorActionPreference='Continue';if(Test-Path $work){& terraform "-chdir=$work" destroy -auto-approve -input=false -no-color "-var=run_id=$runId" "-var=subnet_id=$subnet" '-var=catalog_path=fixtures/catalog-v2.json' 2>$null|Out-Null};if($subnet){& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-subnet --subnet-id $subnet 2>$null|Out-Null};if($vpc){& aws.exe --endpoint-url $LocalstackEndpoint --region us-east-1 ec2 delete-vpc --vpc-id $vpc 2>$null|Out-Null};$env:AWS_ACCESS_KEY_ID=$oldA;$env:AWS_SECRET_ACCESS_KEY=$oldS;$env:AWS_DEFAULT_REGION=$oldR;if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force};$ErrorActionPreference=$old
}
if($failure){throw $failure}
