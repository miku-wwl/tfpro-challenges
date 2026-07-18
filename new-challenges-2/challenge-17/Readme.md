# Challenge 17：Saved Plan 与当前源码的发布边界

发布流程最容易出现的误区，是审阅一个 plan，却应用了后来重新计算的动作。本题先保存
Release v1 的计划，再只修改源码为 v2，随后应用原 plan。你会从 state 和 S3 API 看到：
保存的计划不会因为 `.tf` 文件随后改变而自动变成 v2。

## 官方考试目标

- **1b**：使用 `terraform plan` 及其选项生成执行计划
- **1c**：使用 `terraform apply` 及其选项应用变更
- **3c**：在自动化环境中使用非交互 Terraform workflow

本题使用 Terraform `>= 1.6.0, < 2.0.0`、AWS provider `5.80.0` 与 LocalStack S3。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-17
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
Invoke-RestMethod http://localhost:4566/_localstack/health
```

Starter 只含两个源文件。`aws_s3_bucket.release` 的固定物理名称是
`tfpro-c17-saved-plan`，初始 `Release` tag 为 `v1`；没有 init、state 或 plan 产物。

## Task 1：初始化并验证 v1 源码

```powershell
terraform init -input=false
terraform fmt -check
terraform validate
terraform plan -input=false
```

完整 plan 应只包含一个 bucket create，计划中的 `Release` 是 `v1`。此时不要 apply。

## Task 2：保存并审阅唯一获准的 v1 Plan

```powershell
terraform plan -input=false '-out=release-v1.tfplan'
terraform show release-v1.tfplan

$v1Plan = terraform show -json release-v1.tfplan | ConvertFrom-Json
$v1Change = $v1Plan.resource_changes |
  Where-Object address -eq 'aws_s3_bucket.release'
$v1Change.change.actions
$v1Change.change.after.tags.Release
```

Actions 应只有 `create`，最后一行应输出 `v1`。`release-v1.tfplan` 是包含完整计划信息的
二进制 artifact，不是可编辑 HCL，也不应提交到仓库。

## Task 3：只把当前源码推进到 v2

在 `challenge-17.tf` 中只把 `Release = "v1"` 改成 `Release = "v2"`，bucket 名称与其他
字段都不变。然后比较旧 plan 和当前源码计算的新 plan：

```powershell
terraform fmt -check
terraform validate
terraform show release-v1.tfplan | Select-String -Pattern 'Release','v1'
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

旧 plan 仍包含 `v1`；新 plan 从当前源码计算，包含 `v2`。因为资源尚未创建，详细退出码
应为 `2`。不要把新 plan 保存到旧文件名，也不要运行无参数 apply。

## Task 4：应用被审阅的同一份 v1 Plan

```powershell
terraform apply -input=false release-v1.tfplan
terraform output -json release_contract
terraform state show aws_s3_bucket.release
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c17-saved-plan `
  --query 'TagSet[?Key==`Release`].Value | [0]' `
  --output text
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

Output、state 与 API 都必须显示 `v1`，尽管当前 `.tf` 已写成 v2。最后一个 fresh plan
应退出 `2`，只计划把 tag 原地更新到 v2。这证明 apply saved plan 使用已审阅 artifact，
不是重新解释当前源码。

## Task 5：生成并应用新的 v2 Plan 以收敛源码

```powershell
terraform plan -input=false '-out=release-v2.tfplan'
terraform show release-v2.tfplan
terraform apply -input=false release-v2.tfplan
terraform output -json release_contract
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c17-saved-plan `
  --query 'TagSet[?Key==`Release`].Value | [0]' `
  --output text
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

这次审阅和应用的是同一份 v2 plan。API 应返回 `v2`；最终退出码必须是 `0`。

## Task 6：销毁并恢复 Starter

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c17-saved-plan
$LASTEXITCODE
```

State 应为空且 API 退出码非零。销毁后把练习中唯一的源码修改恢复到 starter，再删除已知
运行产物：

```powershell
git restore --source=HEAD -- .\challenge-17.tf
Remove-Item -LiteralPath .\.terraform -Recurse -Force
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,`
  .\terraform.tfstate.backup,.\release-v1.tfplan,.\release-v2.tfplan `
  -Force -ErrorAction SilentlyContinue
git diff --exit-code -- .\challenge-17.tf
Get-ChildItem -Force | Select-Object -ExpandProperty Name
```

最终源码重新是 v1，目录只保留 `Readme.md` 和 `challenge-17.tf`。

## Terraform 1.6 与 LocalStack 边界

- 本题只使用 Terraform 1.6 已有的 saved plan、`terraform show -json`、
  `-input=false` 与 `-detailed-exitcode`。
- `terraform apply release-v1.tfplan` 不接受也不需要 `-auto-approve`；保存计划已经是明确的
  待执行 artifact。
- Saved plan 会包含配置值，可能也含敏感数据；不能把它当作无害日志。
- Saved plan 若对应的 state 已被其他操作改变，会变成 stale；本题在 v1 plan 与 apply 之间
  只改源码，不执行其他 state 写操作。
- LocalStack 模拟 S3 tag API；真实发布仍应把 plan artifact 当成受控制品存储与授权。
