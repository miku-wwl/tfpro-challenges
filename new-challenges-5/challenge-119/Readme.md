# Challenge 119：Git module 的 tag 升级、SHA 固定与基础设施变更分离

module 代码升级和 module inputs 变化是两种不同事件。这个练习先用 Git tag `v5.1.2` 部署一个 security
group，再把 source 升级到 `v5.2.0`，随后固定为该版本的完整 commit SHA。只要 module 对现有 inputs 的行为
没有改变，升级计划应为零资源动作；最后你会单独修改 ingress input，观察真正的远端变更。

## 官方考试目标

- **1a**：在 module source 改变后初始化工作目录
- **1b / 1c**：保存、审阅并应用执行计划
- **3a**：管理 module 版本选择
- **4b / 4c**：调用并升级 module
- 辅助使用 **1e**：用 state 与远端 API 区分代码升级和对象变化

考纲依据为 [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。
本题使用 Terraform 1.6 的
[Git module source](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources#generic-git-repository)。远程 module
只管理考试资源清单中的 `aws_security_group` 与 `aws_security_group_rule`，AWS provider 固定为 `5.80.0`，
服务端为 LocalStack Ultimate。

## Starter 状态

```powershell
Set-Location .\new-challenges-5\challenge-119
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

git --version
aws --endpoint-url=http://localhost:4566 sts get-caller-identity
```

目录只有 `Readme.md` 与 `challenge-119.tf`。Starter source 固定在 Git tag `v5.1.2`，创建：

- security group `tfpro-c119-git-release`；
- 来自 `10.119.0.0/16` 的 TCP 22 ingress；
- 用于核对 ID、名称和 VPC 的 `release_contract` output。

## Task 1：部署 `v5.1.2` 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c119-v5-1-2.tfplan'
terraform show .\c119-v5-1-2.tfplan
terraform apply .\c119-v5-1-2.tfplan
Remove-Item -LiteralPath .\c119-v5-1-2.tfplan

$baseline = terraform output -json release_contract | ConvertFrom-Json
terraform state list
terraform plan
```

应创建一个 security group 和一条 ingress rule。记录 `$baseline.id`；最后 plan 为 `No changes`。检查 module
cache 当前 commit：

```powershell
$moduleManifest = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$releaseModule = $moduleManifest.Modules |
  Where-Object { $_.Key -eq "release" }
git -C $releaseModule.Dir rev-parse HEAD
```

`v5.1.2` 的 commit 应为 `20e107...` 开头。

## Task 2：把 tag 升级到 `v5.2.0`

只把 source 的 `ref=v5.1.2` 改为 `ref=v5.2.0`。不要修改 name、VPC、ingress 或 tags。

```powershell
terraform plan
```

第一个 plan 应要求重新初始化。然后执行：

```powershell
terraform init -upgrade
terraform validate
terraform plan '-out=c119-v5-2-0.tfplan'
terraform show .\c119-v5-2-0.tfplan
```

保存的计划必须是 `No changes`。这两个 module 版本对本题使用的 inputs 生成相同 resource 配置；source
升级并不自动要求重建远端对象。删除计划并再次读取 cache commit：

```powershell
Remove-Item -LiteralPath .\c119-v5-2-0.tfplan
$moduleManifest = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$releaseModule = $moduleManifest.Modules |
  Where-Object { $_.Key -eq "release" }
git -C $releaseModule.Dir rev-parse HEAD
```

此时 commit 应是 `eb9fb97125c6fd9556287193150a628cdddf5c4d`。

## Task 3：把可移动 tag 换成完整 SHA

把 source 改为：

```hcl
source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git?ref=eb9fb97125c6fd9556287193150a628cdddf5c4d"
```

```powershell
terraform init -upgrade
terraform fmt -check
terraform validate
terraform plan '-out=c119-sha.tfplan'
terraform show .\c119-sha.tfplan
```

计划仍应严格 `No changes`。tag 和 SHA 当前解析为同一 commit；完整 SHA 把选择写死在配置中，不依赖 tag
以后是否被移动。删除空计划：

```powershell
Remove-Item -LiteralPath .\c119-sha.tfplan
```

## Task 4：证明 module 升级没有改变对象身份

```powershell
$current = terraform output -json release_contract | ConvertFrom-Json
$baseline
$current

terraform state show 'module.release.aws_security_group.this[0]'
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $current.id `
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId,Ingress:IpPermissions}'
```

`$current.id` 必须等于 `$baseline.id`，state address 也不变。`.terraform.lock.hcl` 中 AWS provider 仍为
`5.80.0`；Git module tag/SHA 不会写入 provider lockfile。

## Task 5：单独修改 input，观察真正的远端动作

保持完整 SHA source，只把 `cidr_blocks` 从一个 CIDR 字符串改为：

```hcl
cidr_blocks = "10.119.0.0/16,10.219.0.0/16"
```

```powershell
terraform fmt
terraform validate
terraform plan '-out=c119-ingress.tfplan'
terraform show .\c119-ingress.tfplan
```

这一次计划必须出现 ingress rule 的远端变更；具体显示更新还是替换取决于 provider schema，但不能替换 security
group 本身。确认后应用并验收：

```powershell
terraform apply .\c119-ingress.tfplan
Remove-Item -LiteralPath .\c119-ingress.tfplan

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $current.id `
  --query 'SecurityGroups[].IpPermissions[].IpRanges[].CidrIp'
terraform plan
```

API 应显示两个 CIDR，最终 plan 为 `No changes`。能够区分 Task 2/3 的 module 代码选择变化和本 Task 的
module input 变化，是本题核心。

## Task 6：销毁并恢复 `v5.1.2` starter

在当前完整 SHA、双 CIDR 配置下销毁：

```powershell
$securityGroupId = (terraform output -json release_contract | ConvertFrom-Json).id
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $securityGroupId
```

state 应为空，API 应报告目标 group 不存在。然后恢复：

- source 中 `ref=v5.1.2`；
- `cidr_blocks = "10.119.0.0/16"`。

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能有 `Readme.md` 和 starter `challenge-119.tf`。

## 边界提醒

- source 变化后必须 init；是否有远端资源动作由初始化后的 plan 决定。
- 从 module cache 运行 `git rev-parse` 仅用于本地诊断；可复现合同仍是配置里的完整 source/ref。
- `terraform init -upgrade` 允许重新选择/下载依赖，但不会升级 Terraform CLI 本身。
- tag 比 branch 更明确，完整 commit SHA 比可移动 tag 更可复现。
- module changelog 可帮助评估升级，但不能代替对当前配置的 plan 审阅。
