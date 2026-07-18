# Challenge 36：区分 Core 约束、Provider 约束与 Lockfile 选择

这个练习从一份很小但可执行的 toolchain 合同开始。你会分别观察
`required_version`、`required_providers` 与 `.terraform.lock.hcl` 的职责，制造可控的
版本冲突，再用 `terraform init -upgrade` 和只读 lockfile 模式验证选择结果。

## 官方考试目标

- **3a**：Manage the Terraform binary, providers, and modules using version constraints
- **5b**：Configure providers, including aliasing, versioning, sourcing, and managing upgrades

辅助复习 Terraform CLI 工作流。本题 starter 要求 Terraform `>= 1.6.0, < 2.0.0`，
AWS provider 精确固定为 `5.80.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-36
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

目录只有两个源文件。配置使用 caller identity 和 `terraform_data.toolchain` 发布当前
约束合同；没有预生成 provider、lockfile 或 state。

## Task 1：初始化并记录实际选择

```powershell
terraform version
terraform init
terraform fmt -check
terraform validate
terraform providers
Get-Content -LiteralPath .\.terraform.lock.hcl
```

预期 lockfile 记录 AWS `5.80.0` 与校验和。Core Terraform 不会作为 provider 写进
lockfile。

## Task 2：部署 Toolchain 基线

```powershell
terraform plan '-out=toolchain.tfplan'
terraform show toolchain.tfplan
terraform apply toolchain.tfplan
Remove-Item -LiteralPath .\toolchain.tfplan
terraform output starter_toolchain
terraform plan
```

最终 plan 应为 `No changes`。输出中的字符串是本实验声明的合同，不是 CLI 自动读取的
隐藏版本变量。

## Task 3：制造并恢复 Core 版本冲突

临时把 `required_version` 改为一个排除你当前 CLI 的范围，例如当前 CLI 低于 1.15 时
使用 `>= 1.15.0, < 2.0.0`。

```powershell
terraform validate
terraform plan
```

两者应在读取 provider resource 之前失败，并明确当前 Terraform 不满足 core constraint。
随后恢复 `>= 1.6.0, < 2.0.0`：

```powershell
terraform validate
terraform plan
```

应重新成功且 `No changes`。

## Task 4：放宽 Provider 约束并受控升级

把 AWS 约束临时改为 `~> 5.80`，然后运行：

```powershell
terraform init -upgrade
terraform providers
Select-String -Path .\.terraform.lock.hcl -Pattern 'version|constraints'
terraform plan
```

init 可选择约束允许的较新 5.x 版本，并更新 lockfile；具体补丁/次版本取决于 registry
当前可用版本。plan 应继续描述同一逻辑配置。不要把某个在线最新版本写成固定预期。

## Task 5：恢复精确版本并验证只读 Lockfile

将源码中的 provider 约束恢复为 `5.80.0`：

```powershell
terraform init -upgrade
terraform providers
terraform init -lockfile=readonly
terraform validate
terraform plan
```

lockfile 与配置应再次选择 5.80.0，只读 init 不应改文件。若 lockfile 不满足约束，
`-lockfile=readonly` 必须失败，而不是静默重写。

## Task 6：从输出、State 与 API 验收并清理

```powershell
terraform apply -auto-approve
terraform output starter_toolchain
terraform state show terraform_data.toolchain
aws --endpoint-url=http://localhost:4566 sts get-caller-identity
terraform plan
terraform destroy -auto-approve
```

account ID 应与 STS 一致，最终稳定 plan 为 `No changes`。销毁后 state 应为空。删除
`.terraform`、`.terraform.lock.hcl`、state/backup 和临时 plan，目录恢复为两个源文件。

## LocalStack 提醒

- Provider 下载来自 registry，不来自 LocalStack；离线环境需预先准备 plugin cache。
- LocalStack 只负责 STS API，不能模拟 Terraform registry 的版本解析。
- 本题演示升级流程，但 starter 最终仍精确固定 AWS provider 5.80.0。
