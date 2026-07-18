# Challenge 23：辨认并处理三种 S3 标签漂移计划

一次紧急操作把生产桶的标签改成了人工值。团队既要看清远端对象、Terraform state 和源配置
各自保存了什么，也要选择正确的计划模式恢复声明式合同。本题从一个可部署的 S3 baseline
开始，依次比较 `-refresh=false`、`-refresh-only` 和普通 plan，不能用删除 state 掩盖漂移。

## 官方考试目标

- **1b**：Generate an execution plan using `terraform plan` and its options
- **1c**：Apply configuration changes using `terraform apply` and its options
- **1e**：Manage resource state, including reconciling resource drift

本题只使用官方 AWS 学习资源中的 `aws_s3_bucket`。配置兼容 Terraform
`>= 1.6.0, < 2.0.0`；这里练习的是 Terraform 1.6 已有的刷新模式。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-23
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

目录中只有 `Readme.md` 和 `challenge-23.tf`。Starter 已包含：

- AWS provider `5.80.0`，S3 指向 `http://localhost:4566`；
- `aws_s3_bucket.exercise`，名称为 `tfpro-c23-drift`；
- 一组由 Terraform 管理的基线标签及 `bucket_contract` 输出。

开始前确认 LocalStack 的 S3 服务已运行，目录中没有 `.terraform`、lockfile、state 或 plan。

## Task 1：建立可重复的受管基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform show -no-color .\baseline.tfplan
terraform apply .\baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
terraform plan
```

第一次计划应创建 1 个 bucket；应用后普通 plan 应显示 `No changes`。记录配置合同：

```powershell
terraform output -json bucket_contract | ConvertFrom-Json
terraform state show aws_s3_bucket.exercise
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c23-drift
```

state 与 API 中的 `Environment` 应为 `managed`，`Owner` 应为 `terraform`。

## Task 2：制造只发生在 API 侧的漂移

模拟值班人员绕过 Terraform，把完整 TagSet 替换为人工值：

```powershell
aws --endpoint-url=http://localhost:4566 s3api put-bucket-tagging `
  --bucket tfpro-c23-drift `
  --tagging 'TagSet=[{Key=Name,Value=tfpro-c23-drift},{Key=Challenge,Value=23},{Key=Environment,Value=emergency},{Key=Owner,Value=operator}]'

aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c23-drift
terraform state show aws_s3_bucket.exercise
```

API 应显示 `emergency/operator`，而尚未刷新的 state 仍显示 `managed/terraform`。不要修改
`challenge-23.tf`，否则就无法区分远端漂移与配置变更。

## Task 3：证明 `-refresh=false` 使用旧 state

```powershell
terraform plan -refresh=false '-out=no-refresh.tfplan'
terraform show -no-color .\no-refresh.tfplan
Remove-Item -LiteralPath .\no-refresh.tfplan
```

计划应显示 `No changes`：它比较的是源配置与刷新前的 state，并不代表远端对象没有漂移。
再次查询 API，人工标签应仍然存在。

## Task 4：用 refresh-only 接受远端事实到 state

```powershell
terraform plan -refresh-only '-out=refresh.tfplan'
terraform show -no-color .\refresh.tfplan
terraform apply .\refresh.tfplan
Remove-Item -LiteralPath .\refresh.tfplan
terraform state show aws_s3_bucket.exercise
```

refresh-only 计划应报告 Terraform 之外发生的变化；应用它只更新 state，不会把 API 标签改回
源配置。此时 state 与 API 都应显示 `emergency/operator`。

## Task 5：用普通计划恢复配置意图

```powershell
terraform plan '-out=reconcile.tfplan'
terraform show -no-color .\reconcile.tfplan
terraform apply .\reconcile.tfplan
Remove-Item -LiteralPath .\reconcile.tfplan

aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c23-drift
terraform plan
```

普通计划应提出一次原地 update，把标签恢复为 `managed/terraform`；应用后 API 应符合
源配置，第二次 plan 应显示 `No changes`。

## Task 6：从配置、State 和 API 验收并清理

```powershell
terraform output -json bucket_contract | ConvertFrom-Json
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c23-drift
terraform destroy -auto-approve
```

销毁后 `terraform state list` 应为空，下面的 API 调用应返回 bucket 不存在：

```powershell
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c23-drift

Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate, .\terraform.tfstate.backup `
  -ErrorAction SilentlyContinue
Get-ChildItem -File -Filter '*.tfplan' | Remove-Item -Force
Get-ChildItem -Force | Select-Object Name
```

最终目录应只剩 `Readme.md` 和 `challenge-23.tf`。

## LocalStack 提醒

- LocalStack 是练习后端，不是正式考试中的 AWS；S3 标签 API 的返回顺序不具业务含义。
- `-refresh=false` 可能隐藏漂移，不能作为日常“确认无变更”的替代命令。
- refresh-only 接受远端事实到 state，但不会自动判断人工修改是否正确；恢复还是接受漂移是操作决策。
