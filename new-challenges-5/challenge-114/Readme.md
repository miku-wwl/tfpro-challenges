# Challenge 114：Git 子目录、浅克隆与不可组合的提交引用

这个练习从 Git 仓库里的 `modules/http-80` 子目录模块开始。你会先部署一个真实的
LocalStack security group，再给 Git source 增加浅克隆参数，随后亲手验证一个很容易被忽略的边界：
`depth=1` 可以和 branch/tag 一起使用，却不能直接把任意 commit SHA 当作浅克隆分支。最后你会改用完整
commit SHA 获得可复现的模块版本。

## 官方考试目标

- **1a**：初始化 Terraform 工作目录，并理解 `terraform init` 选项
- **3a**：使用 Terraform、provider 与 module 的版本约束
- **4b**：在配置中使用 module
- **4c**：管理和升级 module 版本
- 辅助使用 **1b / 1c / 1e**：审阅 plan、应用变更并检查 state

考纲依据为 [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。
本题遵守 Terraform 1.6 的
[module source 语法](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)。只使用考试资源清单内的
`data.aws_subnet`、`aws_security_group` 与 `aws_security_group_rule`；后两个资源由远程模块创建。

## 开始之前

启动 LocalStack Ultimate，确保主机可以访问 GitHub，然后进入目录：

```powershell
Set-Location .\new-challenges-5\challenge-114
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

git --version
aws --endpoint-url=http://localhost:4566 sts get-caller-identity
```

Starter 只有 `Readme.md` 与 `challenge-114.tf`。配置通过下面的 source 下载 Git 仓库中的一个子目录：

```hcl
git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git//modules/http-80?ref=v5.2.0
```

注意两个连续斜杠 `//`：它们分隔仓库地址和仓库内子目录；查询参数必须放在子目录之后。模块会在默认 VPC
中创建固定名称 `tfpro-c114-web` 的 security group。

## Task 1：初始化并证明子目录模块真的在工作

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c114-baseline.tfplan'
terraform show .\c114-baseline.tfplan
terraform apply .\c114-baseline.tfplan
Remove-Item -LiteralPath .\c114-baseline.tfplan
```

plan 应创建 1 个 security group 和 3 条 rule：CIDR HTTP ingress、self ingress 与 egress。检查完整 module
地址，而不是只看根模块：

```powershell
terraform state list
terraform output starter_web_contract
Get-Content -Raw .\.terraform\modules\modules.json

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --filters Name=group-name,Values=tfpro-c114-web `
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId,Ingress:IpPermissions}'
```

state 中的资源地址应位于 `module.web.module.sg` 下；这证明 `http-80` 子模块内部又调用了仓库根模块。
API 应显示 TCP 80 来自 `10.114.0.0/16`。再次运行 `terraform plan`，预期 `No changes`。

## Task 2：给 tag 引用增加浅克隆

把 module source 改成下面的形式；只改变 source，不改变任何 module input：

```hcl
source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git//modules/http-80?depth=1&ref=v5.2.0"
```

先直接运行一次 plan：

```powershell
terraform plan
```

预期失败并提示 module source 已改变、需要重新初始化。然后执行：

```powershell
terraform init -upgrade
terraform validate
terraform plan
```

重新下载应成功，最终 plan 必须是 `No changes`。`depth=1` 只改变 Git 下载策略，不应改变远端
security group 或 Terraform state 的资源地址。

## Task 3：验证 shallow clone 与原始 SHA 的失败边界

`v5.2.0` 对应的完整 commit SHA 是：

```text
eb9fb97125c6fd9556287193150a628cdddf5c4d
```

保留 `depth=1`，只把 `ref` 改成这个 SHA，然后运行：

```powershell
terraform init -upgrade
```

这一步**预期失败**。Git 的浅克隆实现会把 `ref` 传给 clone 的 branch/tag 选择逻辑，原始 commit SHA
不是可直接克隆的远程分支。错误通常会包含找不到 remote branch 或下载 module 失败。不要 apply，也不要把
这个错误当成 LocalStack 故障。

失败后检查现有基础设施仍然存在：

```powershell
terraform state list
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --filters Name=group-name,Values=tfpro-c114-web `
  --query 'SecurityGroups[].GroupId'
```

失败发生在 module 安装阶段，不会修改 state 或远端对象。

## Task 4：去掉 depth，用完整 commit SHA 固定版本

删除 `depth=1&`，保留完整 SHA：

```hcl
source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git//modules/http-80?ref=eb9fb97125c6fd9556287193150a628cdddf5c4d"
```

```powershell
terraform init -upgrade
terraform fmt -check
terraform validate
terraform plan '-out=c114-sha.tfplan'
terraform show .\c114-sha.tfplan
```

plan 必须是 `No changes`：tag 和 SHA 指向相同代码，module input 与 state address 都没有变化。删除空计划：

```powershell
Remove-Item -LiteralPath .\c114-sha.tfplan
Get-Content -Raw .\.terraform\modules\modules.json
```

`modules.json` 会记录 source 与安装目录，但 `.terraform.lock.hcl` 只锁定 provider，不会替你锁定 Git module。
真正固定 Git module 的是 source 中的完整 SHA。

## Task 5：从 module output、state 与 API 三向验收

```powershell
$contract = terraform output -json starter_web_contract | ConvertFrom-Json

terraform state list
terraform state show 'module.web.module.sg.aws_security_group.this[0]'
terraform plan

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $contract.security_group_id `
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId,Ingress:IpPermissions}'
```

output、state 与 API 的 ID、名称和 VPC 必须一致；API 的 ingress 应同时包含来自
`10.114.0.0/16` 的 HTTP 80 和模块声明的 self ingress，egress 则位于 `IpPermissionsEgress`。最终 plan
必须显示 `No changes`。

## Task 6：销毁并恢复 starter

在 SHA 固定的有效配置下先销毁：

```powershell
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --filters Name=group-name,Values=tfpro-c114-web `
  --query 'SecurityGroups'
```

`terraform state list` 和 API 的目标结果都应为空。把 source 恢复为 starter 的 tag 形式：

```hcl
source = "git::https://github.com/terraform-aws-modules/terraform-aws-security-group.git//modules/http-80?ref=v5.2.0"
```

然后删除运行产物：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

目录最终只能剩下 `Readme.md` 和 `challenge-114.tf`，且 `.tf` 必须恢复为最初的 tag source。

## 边界提醒

- `//subdirectory` 是 Git module source 的一部分，不是文件系统绝对路径。
- `version` argument 不能代替 Git 的 `ref`；Registry module 才支持 module `version`。
- branch 和可移动 tag 可能被重指向；完整 commit SHA 的可复现性更强。
- 本题只练 source、安装和版本选择，不扩展到 Git 凭证、Git LFS、submodule 或 CI 发布流程。
