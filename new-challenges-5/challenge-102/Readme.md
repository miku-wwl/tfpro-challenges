# Challenge 102：观察 Registry Module 的版本选择与 `init -upgrade`

本题已经使用 Registry module 创建一个真实 security group。你不会修改资源输入，而会
依次改变 module version constraint，观察普通 `terraform init` 与
`terraform init -upgrade` 如何选择版本，并证明升级 module 不必产生资源动作。

## 官方考试目标

- **1a**：Initialize a configuration using `terraform init` and its options
- **3a**：管理 provider 与 module version constraints
- **4b / 4c**：调用 Registry module，并安全演进 module version

参考 [Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
和 [Terraform 1.6 Module Sources](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)。
module 内只创建考纲白名单中的 `aws_security_group` 与
`aws_security_group_rule`。

## 开始之前

本题要求 LocalStack Ultimate 正在运行，并且当前机器可以访问 Terraform Registry：

```powershell
Set-Location .\new-challenges-5\challenge-102
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

aws --endpoint-url=http://localhost:4566 ec2 describe-subnets `
  --filters Name=availability-zone,Values=us-east-1a
```

## Starter 状态

Starter 已提供：

- 默认 `us-east-1a` subnet 查询；
- Registry source `terraform-aws-modules/security-group/aws`；
- 精确 module version `5.1.0`；
- security group `tfpro-c102-web`；
- HTTPS `443` ingress 与 `10.102.0.0/16` CIDR；
- `security_group_contract` output。

不要修改 module inputs。整个练习只改变 `version` constraint 和本地安装选择。

## Task 1：部署精确版本 `5.1.0` 基线

从干净目录初始化并保存计划：

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c102-v510.tfplan'
terraform show .\c102-v510.tfplan
terraform apply .\c102-v510.tfplan
Remove-Item -LiteralPath .\c102-v510.tfplan
```

检查安装记录和资源：

```powershell
$modules = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$modules.Modules |
  Where-Object Key -eq "web" |
  Select-Object Key,Source,Version

terraform output security_group_contract
terraform state list
```

`Version` 必须是 `5.1.0`。state 中所有托管资源都应位于 `module.web` 下。

## Task 2：放宽到 Patch 范围，但使用普通 Init

把 module constraint 从 `5.1.0` 改为：

```hcl
version = "~> 5.1.0"
```

该约束允许 `5.1.x`，但不允许 `5.2.0`。只运行普通 init：

```powershell
terraform init

$modules = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$modules.Modules |
  Where-Object Key -eq "web" |
  Select-Object Key,Source,Version

terraform plan
```

因为已经安装的 `5.1.0` 仍满足新约束，普通 init 应继续使用 `5.1.0`；计划必须
`No changes`。不要删除 `.terraform`，否则就不再是在观察“保持已安装版本”。

## Task 3：用 `init -upgrade` 选择 `5.1.2`

保持 `~> 5.1.0` 不变，执行：

```powershell
terraform init -upgrade

$modules = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$modules.Modules |
  Where-Object Key -eq "web" |
  Select-Object Key,Source,Version

terraform plan '-out=c102-v512.tfplan'
terraform show .\c102-v512.tfplan
Remove-Item -LiteralPath .\c102-v512.tfplan
```

安装记录必须变为 `5.1.2`。本次 module patch release 不改变本题使用的资源输入，
所以计划必须严格 `No changes`，不要运行 apply。

## Task 4：扩大 Minor 范围并选择 `5.2.0`

把 constraint 改为：

```hcl
version = ">= 5.1, < 5.3"
```

然后显式要求升级：

```powershell
terraform init -upgrade

$modules = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$modules.Modules |
  Where-Object Key -eq "web" |
  Select-Object Key,Source,Version

terraform plan '-out=c102-v520.tfplan'
terraform show .\c102-v520.tfplan
Remove-Item -LiteralPath .\c102-v520.tfplan
```

Terraform 应选择允许范围内较新的 `5.2.0`。计划仍必须 `No changes`：module
代码版本变化不等于一定要修改远端资源。

## Task 5：区分 Provider Lock 与 Module Cache

检查 provider lock 和 module 安装记录：

```powershell
terraform providers
Select-String -Path .\.terraform.lock.hcl -Pattern 'hashicorp/aws'
Select-String -Path .\.terraform.lock.hcl -Pattern 'security-group'

$contract = terraform output -json security_group_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 ec2 describe-security-group-rules `
  --filters "Name=group-id,Values=$($contract.id)" `
  --query 'SecurityGroupRules[].{Egress:IsEgress,From:FromPort,To:ToPort,Protocol:IpProtocol,CIDR:CidrIpv4}'

terraform plan
```

lockfile 应记录 AWS provider `5.80.0`，但没有 module 条目；module 版本在
`modules.json` 中应为 `5.2.0`。API 仍应显示 HTTPS `443` 与原 CIDR，最终 plan
必须 `No changes`。

## Task 6：销毁并恢复精确版本 Starter

先保存 SG ID，再销毁：

```powershell
$securityGroupId = (terraform output -json security_group_contract | ConvertFrom-Json).id
terraform state list
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $securityGroupId
```

state 应为空；API 应报告 security group not found。把 module constraint 恢复为精确
`5.1.0`，确保其余 starter 内容不变，然后删除运行产物：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能剩 `Readme.md` 与 `challenge-102.tf`。

## 易错点

- 普通 `init` 会保留仍满足约束的已安装 module；`init -upgrade` 才主动重选。
- `~> 5.1.0` 不允许 `5.2.0`；`>= 5.1, < 5.3` 允许。
- dependency lock file 锁 provider，不锁 Registry module。
- 不要为了“升级”手工编辑 `.terraform/modules/modules.json`。
