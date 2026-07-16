# Challenge 98：Saved Plan JSON 的人工发布审计

人类可读 plan 适合交互审阅，自动化门禁则需要稳定地读取 plan JSON。本题先部署 EC2
release v1，再保存一个会替换 instance 的 v2 plan；你会检查 resource address、actions、
replacement 原因、unknown 值和 sensitive 标记，只有门禁符合预期才应用**同一份** plan。
整个流程不生成任何评分或辅助脚本。

## 考纲定位

- **1b**：Generate an execution plan using `terraform plan` and its options
- **1c**：Apply configuration changes using `terraform apply` and its options
- **2f**：Analyze best practices for managing sensitive data
- **3c**：Use the Terraform workflow in automation

范围依据：[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。

## 开始前

```powershell
Set-Location .\new-challenges-4\challenge-98
curl.exe http://localhost:4566/_localstack/health
```

Starter 使用 LocalStack EC2/STS endpoints，查询已有 Ubuntu AMI，并创建一台
`tfpro-c98-release` instance。`bootstrap_token` 只是明确标注的假值；任何真实 secret 都
不能放进练习、saved plan 或导出的 JSON。

## 任务

### Task 1：部署并记录 v1 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=release-v1.tfplan'
terraform show release-v1.tfplan
terraform apply release-v1.tfplan
terraform output release_contract
```

输出 serial 必须为 `1`。记录 instance ID；v2 受控替换后它应改变。

### Task 2：生成非交互 v2 Saved Plan

把 `release_serial` 的 default 从 `1` 改为 `2`，然后执行：

```powershell
terraform plan -input=false -detailed-exitcode '-out=release-v2.tfplan'
$LASTEXITCODE
```

退出码必须为 `2`，表示存在变更，而不是失败。人类可读审阅必须显示
`aws_instance.release` 因 user data 变化而替换：

```powershell
terraform show release-v2.tfplan
```

此时不要 apply，也不要再修改配置。

### Task 3：把 Plan 转为 JSON 并定位一条资源变更

JSON 是临时敏感制品，写到 challenge 之外：

```powershell
$planJson = Join-Path $env:TEMP 'tfpro-c98-release-v2.json'
terraform show -json release-v2.tfplan | Set-Content -Encoding utf8 $planJson
$plan = Get-Content -Raw $planJson | ConvertFrom-Json
$change = $plan.resource_changes | Where-Object address -eq 'aws_instance.release'
$change.address
$change.change.actions
$change.action_reason
$change.change.replace_paths | ConvertTo-Json -Depth 10 -Compress
$change.change.after_unknown | ConvertTo-Json -Depth 10 -Compress
$change.change.after_sensitive | ConvertTo-Json -Depth 10 -Compress
```

必须只定位到完整地址 `aws_instance.release`，actions 必须同时包含 `delete` 和 `create`；
`after_unknown.id` 应为 true，`after_sensitive.user_data` 应标记敏感边界。

重要：`terraform show -json` 的调用者被视为有权读取整个 plan。Sensitive 标记是给下游
工具的元数据，不是 JSON 加密；所以本题只使用假 token，并把 JSON 当敏感制品处理。

### Task 4：执行最小动作白名单门禁

在当前 PowerShell 对象上执行人工门禁：

```powershell
if ($change.address -ne 'aws_instance.release') { throw 'unexpected address' }
if (($change.change.actions -join ',') -ne 'delete,create') { throw 'unexpected actions' }
if (-not $change.change.after_sensitive.user_data) { throw 'user_data lost its sensitive marker' }
```

三条命令都不应抛错。再确认整份 plan 没有第二个资源动作：

```powershell
$actions = $plan.resource_changes | Where-Object { $_.change.actions -notcontains 'no-op' }
$actions.address
```

输出只能是 `aws_instance.release`。若出现其他地址，应停止发布并重新审阅，而不是扩大
白名单。

### Task 5：应用同一份 Plan 并验证幂等

```powershell
terraform apply -input=false release-v2.tfplan
terraform output release_contract
terraform state show aws_instance.release
terraform plan -input=false -detailed-exitcode
```

最终 serial 为 `2`，instance ID 与 v1 不同，最后命令退出码为 `0`。不能在门禁之后重新
运行一次未保存的 `terraform apply -auto-approve`，那会绕开已审阅的 artifact。

## 最终验收

```powershell
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --filters Name=tag:Name,Values=tfpro-c98-release `
  --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,Serial:Tags[?Key==`Serial`]|[0].Value}'
terraform fmt -check
terraform validate
```

LocalStack 中只能有一台当前 release instance，Serial 为 `2`；Terraform 配置处于 clean
plan 状态。

## 清理

```powershell
terraform destroy -auto-approve
Remove-Item -Force release-v1.tfplan,release-v2.tfplan -ErrorAction SilentlyContinue
Remove-Item -Force $planJson -ErrorAction SilentlyContinue
```

不要提交 plan、plan JSON、state、lockfile 或 `.terraform`。

## Terraform 1.6 边界

本题只依赖 Terraform 1.6 的 saved plan、`terraform show -json`、sensitive value 传播和
`-detailed-exitcode`。不使用 actions、ephemeral/write-only values、mock provider 或
任何 1.7+ 功能。
