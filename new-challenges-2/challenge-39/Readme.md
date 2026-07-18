# Challenge 39：构建无提示、可审计的 Plan/Apply 流程

这个练习把同一份 S3 release 配置放进非交互工作流。你会使用 `-input=false`、
`-detailed-exitcode`、saved plan 和 plan JSON，区分“失败”“无变更”“有变更”，并确保
apply 消费的是刚刚审阅的同一份计划。

## 官方考试目标

- **1b**：Generate an execution plan using `terraform plan` and its options
- **1c**：Apply configuration changes using `terraform apply` and its options
- **3c**：Use the Terraform workflow in automation

使用官方 AWS `aws_s3_bucket` 资源。兼容 Terraform `>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-39
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
$env:TF_IN_AUTOMATION = "1"
```

Starter 定义 `tfpro-c39-release` bucket 和默认 `release_id = "v1"`，因此所有命令都可以
无提示解析输入。尚无 state 或 saved plan。

## Task 1：以 Noninteractive 模式初始化

```powershell
terraform init -input=false
terraform fmt -check
terraform validate
```

预期成功且不出现变量提示。`TF_IN_AUTOMATION` 调整输出呈现，但不会自动接受 apply。

## Task 2：用 Detailed Exit Code 识别首次变更

```powershell
terraform plan -input=false -detailed-exitcode '-out=release-v1.tfplan'
$planExit = $LASTEXITCODE
$planExit
```

首次 plan 应返回 `2`，表示成功且有变更；`0` 表示成功无变更，`1` 才是错误。不要让
CI 把 2 当作普通失败。

```powershell
terraform show .\release-v1.tfplan
terraform show -json .\release-v1.tfplan |
  Set-Content -LiteralPath .\release-v1.plan.json -Encoding utf8
```

人类输出应显示创建一个 bucket；JSON 是临时审计产物。

## Task 3：解析 JSON 并应用同一 Saved Plan

```powershell
$plan = Get-Content .\release-v1.plan.json -Raw | ConvertFrom-Json
$plan.resource_changes |
  Select-Object address,type,name,@{Name='actions';Expression={$_.change.actions -join ','}}

terraform apply -input=false .\release-v1.tfplan
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

解析结果只能有 `aws_s3_bucket.release` 的 create。apply 不应再次生成计划；第二次 plan
应返回 `0`。

## Task 4：发布 V2 并再次区分 Exit Code

把源码默认 `release_id` 改为 `v2`，然后：

```powershell
terraform plan -input=false -detailed-exitcode '-out=release-v2.tfplan'
$LASTEXITCODE
terraform show -json .\release-v2.tfplan |
  Set-Content -LiteralPath .\release-v2.plan.json -Encoding utf8
terraform show .\release-v2.tfplan
```

预期退出码 `2`，计划只更新 Release tag。审阅后应用同一文件：

```powershell
terraform apply -input=false .\release-v2.tfplan
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

最终应返回 `0`。

## Task 5：证明 Input=false 会快速失败

临时删除 `release_id` 的 default，使它成为必填变量；不要设置 `TF_VAR_release_id`：

```powershell
terraform plan -input=false
$LASTEXITCODE
```

预期立即非零失败并报告缺少 required variable，而不是等待键盘输入。随后恢复
`default = "v2"`，运行 `terraform validate` 与 plan，结果应重新为 0。

## Task 6：验收、销毁并清理自动化产物

```powershell
terraform output release_contract
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c39-release
terraform state list
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
terraform destroy -auto-approve -input=false
```

API 的 Release tag 应为 `v2`，稳定 plan 返回 0。销毁后 `head-bucket` 应失败。删除两个
`.tfplan`、两个 `.plan.json`、`.terraform`、lockfile 与 state/backup，再运行：

```powershell
Remove-Item Env:\TF_IN_AUTOMATION
Get-ChildItem -Force
```

目录必须只剩 `Readme.md` 和 `challenge-39.tf`。

## LocalStack 提醒

- Detailed exit code 来自 Terraform CLI，与 LocalStack 无关。
- Saved plan 绑定配置、provider selection 和当时 state；不要跨运行长期保存或复用。
- Plan JSON 可能包含敏感值，应按 state 同等级保护并在练习后删除。
