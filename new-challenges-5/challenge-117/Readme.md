# Challenge 117：Registry 与 Git source 的零基础设施切换

同一个公开 module 可以从 Terraform Registry 安装，也可以直接从它的 GitHub 仓库安装。source 形式改变不代表
远端基础设施一定要改变。本题先用 Registry module 创建 LocalStack security group，再把 module source 切换到
对应的 Git tag 和完整 SHA。你需要用 plan 证明：代码和 inputs 等价时，切换安装来源可以做到零资源动作。

## 官方考试目标

- **1a**：在 source 改变后重新初始化工作目录
- **3a**：管理 module 版本约束
- **4b / 4c**：使用并升级 module，并在保持受管对象身份的前提下重构其 source 配置
- 辅助使用 **1b / 1c / 1e**：审阅 plan、应用 output 变化并核对 state

考纲依据为 [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。
本题遵循 Terraform 1.6 官方
[module sources](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)语法。module 内部只管理考试资源清单里的
`aws_security_group` 与 `aws_security_group_rule`；VPC 来自 `data.aws_subnet`。AWS API 全部指向 LocalStack Ultimate。

## Starter 状态

```powershell
Set-Location .\new-challenges-5\challenge-117
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

git --version
aws --endpoint-url=http://localhost:4566 sts get-caller-identity
```

目录只有 `Readme.md` 和 `challenge-117.tf`。Starter 使用：

```hcl
source  = "terraform-aws-modules/security-group/aws"
version = "5.2.0"
```

它创建固定名称 `tfpro-c117-source-switch` 的 security group，并开放来自 `10.117.0.0/16` 的 TCP 443。
output 中的 `source = "registry"` 是人工维护的合同字段，用来刻意观察 output-only 变化。

## Task 1：部署 Registry 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c117-registry.tfplan'
terraform show .\c117-registry.tfplan
terraform apply .\c117-registry.tfplan
Remove-Item -LiteralPath .\c117-registry.tfplan

terraform output edge_contract
terraform state list
terraform plan
```

应创建一个 security group 和一条 ingress rule，state 地址以 `module.edge` 开头。最后 plan 必须为
`No changes`。记录 API 基线：

```powershell
$contract = terraform output -json edge_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $contract.id `
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId,Ingress:IpPermissions}'
Get-Content -Raw .\.terraform\modules\modules.json
```

## Task 2：只切换到等价 Git tag

把 module source 改成 Git tag，并删除 `version` argument：

```hcl
source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=v5.2.0"
```

暂时不要修改 output 中的人工 `source` 字段。先运行：

```powershell
terraform plan
```

预期提示 module source 已变化并要求重新初始化。然后：

```powershell
terraform init -upgrade
terraform validate
terraform plan '-out=c117-switch.tfplan'
terraform show .\c117-switch.tfplan
```

计划必须是 `No changes`。Registry `5.2.0` 与 Git tag `v5.2.0` 对应相同 module 代码，module label、
inputs 和内部 resource addresses 都没变。切换 source 本身不属于 Terraform state 中的远端资源变更。

```powershell
Remove-Item -LiteralPath .\c117-switch.tfplan
Get-Content -Raw .\.terraform\modules\modules.json
```

## Task 3：让可见合同诚实反映 source

把 `edge_contract.source` 从 `"registry"` 改为 `"git-tag-v5.2.0"`，不要改 module input：

```powershell
terraform fmt
terraform validate
terraform plan '-out=c117-output.tfplan'
terraform show .\c117-output.tfplan
terraform apply .\c117-output.tfplan
Remove-Item -LiteralPath .\c117-output.tfplan
```

plan 应只有 root output 变化，不能更新或替换 security group/rule。output 值属于 state，但不是 LocalStack
远端对象；这解释了为什么 Task 2 可以严格 `No changes`，而本 Task 有 output-only change。

## Task 4：从 tag 进一步固定到完整 commit SHA

把 source 改为 Git `v5.2.0` 对应的完整 SHA：

```hcl
source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=eb9fb97125c6fd9556287193150a628cdddf5c4d"
```

同时把 output 标记改为 `"git-sha-v5.2.0"`。然后：

```powershell
terraform init -upgrade
terraform validate
terraform plan '-out=c117-sha.tfplan'
terraform show .\c117-sha.tfplan
```

预期仍没有基础设施动作，只有 output 标记变化。应用后再次检查：

```powershell
terraform apply .\c117-sha.tfplan
Remove-Item -LiteralPath .\c117-sha.tfplan
terraform plan
terraform state list
```

最终 plan 为 `No changes`，resource addresses 与 Task 1 完全相同。

## Task 5：验证对象身份没有随 source 改变

```powershell
$contract = terraform output -json edge_contract | ConvertFrom-Json

terraform state show 'module.edge.aws_security_group.this[0]'
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $contract.id `
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId,Ingress:IpPermissions}'

Get-Content -Raw .\.terraform\modules\modules.json
Get-Content -Raw .\.terraform.lock.hcl
```

ID 应与 Task 1 记录的一致；名称、VPC 与 TCP 443 ingress 不变。`modules.json` 现在显示 Git SHA source，
而 lockfile 仍只记录 AWS provider。与结对 AI 解释：source 是模块代码的获取方式，resource identity 由
state address 与 provider 远端 ID 共同维持。

## Task 6：销毁并恢复 Registry starter

在有效的 Git SHA 配置下销毁：

```powershell
$securityGroupId = (terraform output -json edge_contract | ConvertFrom-Json).id
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $securityGroupId
```

state 应为空；API 应报告目标 group 不存在。然后同时恢复三处 starter 内容：

1. Registry source `terraform-aws-modules/security-group/aws`；
2. `version = "5.2.0"`；
3. output 标记 `source = "registry"`。

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

目录最终只能有 `Readme.md` 与 starter `challenge-117.tf`。

## 边界提醒

- Registry source 用 `version`；Git source 删除 `version` 并用 `ref`。
- 切换到“看起来同版本”的代码前仍必须审阅 plan，不能假设两个发行物永远等价。
- module source 不保存在 resource state 中，但 module label 和内部 resource address 会影响对象身份。
- 本题不涉及 Registry 发布、签名验证或 Git 认证。
