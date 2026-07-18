# Challenge 19：Saved Destroy Plan、Target Retirement 与配置意图

你接手了一对 S3 buckets：`active` 必须保留，`legacy` 已获准退役。练习先部署两者，再保存
只销毁 legacy 的 targeted destroy plan；随后从源码删除 legacy 声明，最后执行此前审阅的
同一份 destroy artifact。四个观察面必须一致：配置意图、saved plan、state 与 S3 API。

## 官方考试目标

- **1b**：使用 plan 选项生成并审阅 saved destroy plan
- **1d**：使用 Terraform 销毁指定的退役资源与最终环境
- **1e**：安全管理 state，并区分销毁与遗忘对象

本题使用 Terraform `>= 1.6.0, < 2.0.0`、AWS provider `5.80.0` 与 LocalStack S3。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-19
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
Invoke-RestMethod http://localhost:4566/_localstack/health
```

Starter 声明 `tfpro-c19-active` 与 `tfpro-c19-legacy`，但没有 init/state。最终只有 legacy
能在定向退役阶段删除；active 要一直保留到实验总清理。

## Task 1：部署并记录双 Bucket 基线

```powershell
terraform init -input=false
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply baseline.tfplan
terraform state list
aws --endpoint-url=http://localhost:4566 s3api list-buckets `
  --query 'Buckets[?starts_with(Name, `tfpro-c19-`)].Name'
```

State 与 API 都必须出现 active、legacy 两个对象。删除已使用的基线 plan：

```powershell
Remove-Item -LiteralPath .\baseline.tfplan
```

## Task 2：保存只退役 Legacy 的 Destroy Plan

```powershell
terraform plan -destroy -input=false `
  '-target=aws_s3_bucket.legacy' `
  '-out=retire-legacy.tfplan'
terraform show retire-legacy.tfplan

$retirePlan = terraform show -json retire-legacy.tfplan | ConvertFrom-Json
$retireChange = $retirePlan.resource_changes |
  Where-Object address -eq 'aws_s3_bucket.legacy'
$retireChange.change.actions
```

人类可读摘要必须是 **0 to add, 0 to change, 1 to destroy**；JSON action 只能是
`delete`。计划中不能出现 `aws_s3_bucket.active`。此时不要 apply。

## Task 3：把退役决定写进当前配置

从 `challenge-19.tf` 删除完整的 `aws_s3_bucket.legacy` resource block；不要删除 provider、
active bucket 或 output。然后：

```powershell
terraform fmt
terraform validate
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
terraform show retire-legacy.tfplan
```

Fresh plan 应退出 `2`，因为“配置中不再存在、state 中仍存在”表达了销毁 legacy 的声明式
意图。Saved plan 仍只销毁此前审阅的 legacy 地址。源码变化不会改写 plan artifact。

## Task 4：应用同一份 Targeted Destroy Plan

```powershell
terraform apply -input=false retire-legacy.tfplan
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c19-active
$LASTEXITCODE
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c19-legacy
$LASTEXITCODE
```

State 只能保留 `aws_s3_bucket.active`。Active API 退出码必须为 `0`，legacy 必须非零。
这里执行的是远端销毁；若改用 `terraform state rm`，legacy 会被遗留在 LocalStack，语义
完全不同。

## Task 5：用完整 Plan 证明退役已经收敛

```powershell
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
terraform state show aws_s3_bucket.active
terraform output -raw active_bucket
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c19-active
```

完整 plan 退出码必须为 `0`，output 为 `tfpro-c19-active`。Target apply 后的这一步不可
省略，因为只有完整 plan 能确认没有遗漏其他配置动作。

## Task 6：销毁剩余环境并恢复两文件 Starter

当前配置只声明 active，因此普通 destroy 只清理最后的 owner：

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c19-active
$LASTEXITCODE
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c19-legacy
$LASTEXITCODE
```

State 为空，两个 API 检查都应非零。然后恢复 starter 中的 legacy 声明；恢复后不要再次
plan/apply，否则它会作为下一次练习的待创建基线：

```powershell
git restore --source=HEAD -- .\challenge-19.tf
Remove-Item -LiteralPath .\.terraform -Recurse -Force
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,`
  .\terraform.tfstate.backup,.\retire-legacy.tfplan `
  -Force -ErrorAction SilentlyContinue
git diff --exit-code -- .\challenge-19.tf
Get-ChildItem -Force | Select-Object -ExpandProperty Name
```

最终目录只含 `Readme.md` 和恢复到双 bucket 声明的 `challenge-19.tf`。

## Terraform 1.6 与 LocalStack 边界

- `terraform plan -destroy` 生成销毁计划；`-target` 又把范围缩到一个地址。两者组合应当
  谨慎使用，并始终检查计划内容。
- Saved plan 在 state 被其他操作改动后可能 stale；Task 2 到 Task 4 之间不能写 state。
- 删除 resource block 表达“销毁并停止管理”；`state rm` 只表达“停止管理但保留对象”。
- LocalStack 的 bucket 名在本机模拟账号内唯一；本题不涉及真实 AWS 保留期、审批或备份策略。
