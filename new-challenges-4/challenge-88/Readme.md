# Challenge 88：声明式 EC2 Import 与 `-generate-config-out`

这一题包含两个独立 root。`bootstrap` 先模拟旧平台创建一台 EC2 instance，随后明确放弃
它的 state 所有权；`workload` 使用 Terraform 1.6 import block 和
`plan -generate-config-out` 接管同一物理实例。生成的 HCL 只是迁移草稿，必须审阅并
收敛成最小稳定配置后才能 apply。

## 学习目标

- 在两个 root 之间明确交接单个远端对象的 state 所有权；
- 使用 declarative import 与 `-generate-config-out` 建立配置草稿；
- 审阅 provider 生成的 HCL，并以零新增、零变更、零销毁的 import plan 验收。

```text
challenge-88/
├── Readme.md
├── bootstrap/bootstrap.tf
└── workload/workload.tf
```

## 考纲定位

- **1e**：Import existing resources and manage state safely
- **1b / 1c**：生成、审阅并应用 import plan
- 辅助使用 **5b**：Provider schema 驱动的配置生成

## State 边界

- `bootstrap` 起初拥有 `aws_instance.legacy`。
- Task 2 后旧 root 明确停止管理，但远端 instance 保留。
- `workload` 最终只以 `aws_instance.managed` 管理同一 ID。
- 任何时刻都不能让两个 state 同时声称拥有该实例。

## 开始前

使用同一个专用 PowerShell 完成全部任务，以便保留 `$legacyId`：

```powershell
Set-Location .\new-challenges-4\challenge-88
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

## 任务

### Task 1：由旧 Root 创建待接管实例

工作目录：`new-challenges-4/challenge-88/bootstrap`

```powershell
Set-Location .\bootstrap
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
$legacyId = terraform output -raw legacy_instance_id
terraform state show aws_instance.legacy
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $legacyId `
  --query 'Reservations[0].Instances[0].[InstanceId,State.Name]'
```

记录的 ID 必须以 `i-` 开头，API 状态可被读取。此时不要进入 workload import，因为旧
state 仍拥有它。

### Task 2：让旧 Root 停止管理但不销毁实例

```powershell
terraform state rm aws_instance.legacy
terraform state list
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $legacyId `
  --query 'Reservations[0].Instances[0].InstanceId'
```

state 应为空，API 仍返回同一 ID。`state rm` 只是本题建立“已存在但无人管理”前提的
bootstrap 操作。此后不要在 bootstrap 运行 plan/apply；配置仍声明旧资源，普通 plan 会
试图再创建一台。

### Task 3：让 Terraform 生成 Import 配置草稿

工作目录：`new-challenges-4/challenge-88/workload`

```powershell
Set-Location ..\workload
terraform init
terraform validate
terraform plan `
  "-var=legacy_instance_id=$legacyId" `
  '-generate-config-out=generated.tf'
$LASTEXITCODE
Get-Content .\generated.tf
```

Terraform 1.6.6 + AWS Provider 5.80.0 会先读取现有 instance，并为
`aws_instance.managed` 写出 resource block；随后这次实验性 plan 预期以退出码 `1`
结束，因为生成草稿同时写入互斥的 `ipv6_address_count` 与 `ipv6_addresses`。这正是
“生成结果必须人工审阅”的证据，不代表 import 目标不可用。确认 `generated.tf` 已存在后
继续 Task 4，不要 apply，也不要反复运行生成命令覆盖草稿。草稿还可能包含 provider
回读的默认值或 computed 细节；生成不代表这些字段都适合长期维护。

### Task 4：把生成草稿收敛为最小稳定配置

审阅 `generated.tf`，最终只保留真实意图：

- resource 地址固定为 `aws_instance.managed`；
- `ami = "ami-04681a1dbd79675a5"`；
- `instance_type = "t2.micro"`；
- 精确保留 Name、Challenge、Owner 三个 tags；
- 删除只反映 provider 默认值、computed 状态或与其他参数冲突的生成属性。

再加入 `managed_instance` output，至少公开 ID、AMI、instance type 和 Name tag。然后：

```powershell
terraform fmt
terraform validate
terraform plan "-var=legacy_instance_id=$legacyId" '-out=import.tfplan'
terraform show import.tfplan
```

计划必须是 **1 to import, 0 to add, 0 to change, 0 to destroy**。如果有 update 或
replacement，继续对照 `terraform state show`/EC2 API 修正配置，不能 apply。

### Task 5：应用 Import 并证明 ID 未变

```powershell
terraform apply import.tfplan
terraform state list
terraform state show aws_instance.managed
terraform output -json managed_instance
terraform plan "-var=legacy_instance_id=$legacyId" -detailed-exitcode
$LASTEXITCODE
```

state 只包含 `aws_instance.managed`；output ID 必须等于 `$legacyId`；最终退出码为 `0`。
import block 可以保留，已接管对象再次 plan 时不会重复导入。

### Task 6：同时核验 State 与 EC2 API

```powershell
$managed = terraform output -json managed_instance | ConvertFrom-Json
$managed.id -eq $legacyId
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $legacyId `
  --query 'Reservations[0].Instances[0].[InstanceId,ImageId,InstanceType,Tags[?Key==`Name`].Value|[0]]'
```

布尔比较必须为 `True`；API 值应与最终 HCL 合同一致。

## 清理

必须由当前 owner（workload）销毁：

```powershell
terraform destroy -auto-approve "-var=legacy_instance_id=$legacyId"
terraform state list
Remove-Item .\import.tfplan -Force -ErrorAction SilentlyContinue
```

Bootstrap state 已在 Task 2 变空，不要再用 bootstrap destroy 同一实例。若要把练习目录
恢复为 starter，再删除练习时生成的 `workload/generated.tf` 以及两个 root 的
`.terraform/`、lockfile 和 state；仓库交付不包含这些运行产物。

## Terraform 1.6 边界

本题使用 Terraform 1.6 已支持的 import block 与 `-generate-config-out`。Import block
本身不使用 `for_each`（该能力属于 Terraform 1.7），也不使用手工 `terraform import`、
state push 或脚本。
