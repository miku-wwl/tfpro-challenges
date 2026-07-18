# Challenge 22：`state rm` 后安全 Re-import

`terraform state rm` 不会删除远端对象，它只让当前 state 忘记绑定。本题先部署一个 bucket，
预演并执行 state removal，再观察普通 plan 为什么会尝试创建同名对象；最后用
`terraform import` 把同一个 ID 安全接回，而不是 apply 那份创建计划。

## 官方考试目标

- **1e**：安全使用 state CLI、移除绑定并重新导入既有资源
- 辅助使用 **1b / 1c**：识别危险计划，恢复绑定后验证幂等

本题使用 Terraform `>= 1.6.0, < 2.0.0`、AWS provider `5.80.0` 与 LocalStack S3。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-22
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
Invoke-RestMethod http://localhost:4566/_localstack/health
```

Starter 声明 `aws_s3_bucket.managed`，物理名称固定为 `tfpro-c22-managed`。目录中没有
`.terraform`、lockfile、state、backup 或 plan。

## Task 1：部署并确认唯一 Owner

```powershell
terraform init -input=false
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
terraform state list
terraform state show aws_s3_bucket.managed
terraform output -json managed_bucket
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c22-managed
```

State 只有 `aws_s3_bucket.managed`，API 成功。此时当前 local state 是该 bucket 的唯一
Terraform owner。

## Task 2：先 Dry-run，再显式备份并移除绑定

```powershell
terraform state rm -dry-run 'aws_s3_bucket.managed'
terraform state rm '-backup=state-rm.backup' 'aws_s3_bucket.managed'
terraform state list
Get-Item .\state-rm.backup | Select-Object Name,Length
```

Dry-run 与正式命令都只能匹配这个地址。State list 现在为空，且存在显式命名的 backup。
不要编辑 backup，也不要用 `state push` 绕过后续的安全接管流程。

## Task 3：证明 `state rm` 没有调用 S3 Delete

```powershell
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c22-managed
$LASTEXITCODE
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c22-managed
```

API 退出码必须为 `0`，tags 仍包含 Challenge `22`。此刻 HCL 仍声明资源、API 仍有对象，
但 state 不再记录二者的绑定。

## Task 4：识别“同名 Create”危险计划

```powershell
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

退出码应为 `2`，计划尝试 **1 to add**。Terraform 不会按 bucket 名自动猜测“这就是之前
那个对象”。不要 apply：LocalStack 对同 owner 的 CreateBucket 可能表现得比真实迁移更
宽松，依赖这种行为会掩盖 ownership 错误。

## Task 5：用精确 ID 重新 Import 并验证幂等

确认没有第二个 state owner 后，用现有 resource 地址和物理 ID 接回对象：

```powershell
terraform import -input=false `
  'aws_s3_bucket.managed' `
  'tfpro-c22-managed'
terraform state list
terraform state show aws_s3_bucket.managed
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c22-managed
```

Import 必须成功，state 地址恢复，最终 plan 退出码为 `0`。物理 ID 和 tags 与 Task 1
相同；re-import 没有创建第二个 bucket。

## Task 6：由恢复后的 Owner 销毁并清理

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c22-managed
$LASTEXITCODE
```

State 应为空，API 检查应非零。删除本题已知产物，包括含完整旧 state 的 backup：

```powershell
Remove-Item -LiteralPath .\.terraform -Recurse -Force
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,`
  .\terraform.tfstate.backup,.\state-rm.backup `
  -Force -ErrorAction SilentlyContinue
Get-ChildItem -Force | Select-Object -ExpandProperty Name
```

最终只应列出 `Readme.md` 与 `challenge-22.tf`。

## Terraform 1.6 与 LocalStack 边界

- `state rm` 是 ownership 操作，不是 destroy；执行前要精确地址、dry-run、backup 与团队协调。
- Import 需要已存在的 resource 配置、准确远端 ID，以及“没有其他 state owner”的确认。
- Local state backup 与 plan 一样可能含敏感值，不能提交或随意共享。
- LocalStack 只模拟 S3 API。本题特意禁止 apply 同名 create plan，以保持与真实环境一致的
  安全操作习惯。
