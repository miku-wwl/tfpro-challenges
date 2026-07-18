# Challenge 120：Registry + Git 多来源 module 发布合同

这是 101～120 的综合题。Starter 只有默认 subnet 查询和一个 LocalStack S3 bucket；你要逐层加入一个精确
版本的 Registry CIDR module、一个固定完整 SHA 的 Git security-group module，让后者消费前者的 output，最后
把两个 module 的来源、输出和远端 ID 发布为 S3 JSON 合同。每一步只增加一层依赖，便于从 plan 中判断责任边界。

## 官方考试目标

- **1a / 1b / 1c / 1e**：初始化、审阅保存计划、应用并核对 state
- **2c / 2e**：组合表达式、复杂值和结构化 outputs
- **3a**：管理 Registry module version 与 Git module ref
- **4b / 4c**：调用和维护不同来源的 modules
- **5b**：理解 root provider 配置如何被子 module 使用

考纲依据为 [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)，
远程来源语义依据 Terraform 1.6 的
[module sources](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)。本题只使用考纲范围内的
`data.aws_subnet`、`aws_s3_bucket`、`aws_s3_object`、
`aws_security_group` 与 `aws_security_group_rule`；后两个由 Git module 创建。Terraform 兼容
`>= 1.6.0, < 2.0.0`，AWS provider 固定 `5.80.0`，AWS API 只访问 LocalStack Ultimate。

## Starter 状态

```powershell
Set-Location .\new-challenges-5\challenge-120
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

git --version
aws --endpoint-url=http://localhost:4566 sts get-caller-identity
```

目录只有 `Readme.md` 与 `challenge-120.tf`。Starter 已提供：

- 默认 `us-east-1a` subnet 查询及其 VPC ID；
- bucket `tfpro-c120-multi-source`；
- `starter_evidence` output；
- **没有** module，也没有 S3 object。

首次安装 Registry/Git modules 需要外网，但所有 AWS 创建操作都必须落在 LocalStack。

## Task 1：部署最小 AWS starter

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c120-starter.tfplan'
terraform show .\c120-starter.tfplan
terraform apply .\c120-starter.tfplan
Remove-Item -LiteralPath .\c120-starter.tfplan

terraform output starter_evidence
terraform state list
```

计划只应创建一个 S3 bucket；subnet 是只读 data source。确认 output 的 VPC 与 subnet 有值，再运行
`terraform plan`，预期 `No changes`。

## Task 2：加入精确版本的 Registry CIDR module

创建 `module "network"`，要求：

- source 为 `hashicorp/subnets/cidr`；
- `version = "1.0.0"`，使用精确 Registry 版本；
- `base_cidr_block = "10.120.0.0/16"`；
- networks 包含 `app` 与 `ops`，二者 `new_bits = 8`。

增加临时 output `network_contract`，包含 `source = "registry"`、`version = "1.0.0"` 和
`module.network.network_cidr_blocks`。然后：

```powershell
terraform init -upgrade
terraform fmt
terraform validate
terraform plan '-out=c120-network.tfplan'
terraform show .\c120-network.tfplan
terraform apply .\c120-network.tfplan
Remove-Item -LiteralPath .\c120-network.tfplan
terraform output network_contract
```

纯计算 Registry module 不创建 AWS resource，因此计划应只有 output/state 值变化，没有新的远端对象。
`app` 与 `ops` 应得到两个不重叠的 `/24`。

## Task 3：加入完整 SHA 固定的 Git security-group module

创建 `module "edge"`，source 必须是：

```hcl
source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=eb9fb97125c6fd9556287193150a628cdddf5c4d"
```

inputs 要求：

- `name = "tfpro-c120-edge"`，并设置 `use_name_prefix = false`；
- `vpc_id = data.aws_subnet.selected.vpc_id`；
- `ingress_with_cidr_blocks` 只包含 TCP 443；
- `cidr_blocks` **直接引用** `module.network.network_cidr_blocks["app"]`；
- tags 至少含 `Challenge = "120"` 与 `ManagedBy = "Terraform"`。

source 变化后初始化并保存计划：

```powershell
terraform init -upgrade
terraform fmt
terraform validate
terraform plan '-out=c120-edge.tfplan'
terraform show .\c120-edge.tfplan
```

计划应创建一个 security group 和一条 ingress rule；不能新建 VPC/subnet，也不能替换已有 bucket。确认 module
input 在 plan 中使用 Registry module 计算的 `app` CIDR 后应用：

```powershell
terraform apply .\c120-edge.tfplan
Remove-Item -LiteralPath .\c120-edge.tfplan
terraform state list
```

## Task 4：发布跨 module 的 S3 JSON 合同

创建 `aws_s3_object.release_contract`：

- bucket 引用 `aws_s3_bucket.evidence.id`；
- key 为 `release.json`；
- `content_type = "application/json"`；
- content 使用 `jsonencode`，并包含下面的结构化信息：

```text
network.source  = "registry"
network.version = "1.0.0"
network.cidrs   = module.network.network_cidr_blocks
edge.source     = "git"
edge.ref        = "eb9fb97125c6fd9556287193150a628cdddf5c4d"
edge.id         = module.edge.security_group_id
edge.name       = module.edge.security_group_name
edge.vpc_id     = module.edge.security_group_vpc_id
```

不要复制运行时 group ID、VPC ID 或 CIDR。新增最终 output `release_contract`，使用下面这些字段名，方便后续
PowerShell 验收：`bucket`、`key`、`cidrs`、`edge_id`、`edge_name`、`edge_vpc_id`。所有值必须引用现有
resource/module outputs。

```powershell
terraform fmt
terraform validate
terraform plan '-out=c120-contract.tfplan'
terraform show .\c120-contract.tfplan
terraform apply .\c120-contract.tfplan
Remove-Item -LiteralPath .\c120-contract.tfplan
terraform output release_contract
```

计划只应创建 S3 object 和更新 outputs；security group 与 bucket 不应重建。

## Task 5：审计两个 source 与一份 provider lock

```powershell
Get-Content -Raw .\.terraform\modules\modules.json
Get-Content -Raw .\.terraform.lock.hcl
terraform state list
terraform plan

$contract = terraform output -json release_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $contract.edge_id `
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId,Ingress:IpPermissions}'

aws --endpoint-url=http://localhost:4566 s3api get-object `
  --bucket $contract.bucket `
  --key $contract.key `
  .\c120-release.json
Get-Content -Raw .\c120-release.json
Remove-Item -LiteralPath .\c120-release.json
```

`modules.json` 应同时列出 Registry 与 Git source；lockfile 只锁 AWS provider。API 中 TCP 443 的 CIDR 必须
等于 JSON 合同中的 `network.cidrs.app`，ID/name/VPC 也必须一致。最终 plan 为 `No changes`。

## Task 6：反向销毁并恢复无 module starter

先保存远端标识，再在完整配置下销毁：

```powershell
$contract = terraform output -json release_contract | ConvertFrom-Json
$securityGroupId = $contract.edge_id
$bucketName = $contract.bucket

terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $securityGroupId
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket $bucketName
```

state 应为空；security group 与 bucket 查询应报告不存在。然后删除你添加的两个 module blocks、S3 object 和两个
练习 outputs，使 `challenge-120.tf` 精确恢复 starter。最后清理：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能有 `Readme.md` 和 starter `challenge-120.tf`。

## 边界提醒

- Registry module 以 source address + `version` 选择发行版；Git module 以 source URL + `ref` 选择代码。
- module outputs 可以形成依赖边；不要把计算结果复制为硬编码常量。
- root 的默认 AWS provider 会隐式传给使用 `hashicorp/aws` 的 child module；不要在 child module 中硬编码
  LocalStack provider 配置。
- 本题不扩展到发布 Registry module、私有 Registry、Git 凭证或 CI/CD。
