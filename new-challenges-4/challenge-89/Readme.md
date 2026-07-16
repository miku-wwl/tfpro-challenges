# Challenge 89：EC2 Tag Drift 的三种 Refresh 语义

Starter 管理一台带稳定 tags 的 LocalStack EC2 instance。你会先在 EC2 API 外部修改 tags，
再依次比较 `-refresh=false`、refresh-only saved plan 和普通 repair plan。重点是分清：

- 不读取远端时，Terraform 只能相信旧 state；
- refresh-only 让 state 接受现实，但不修复远端；
- 普通 plan 才会根据配置恢复期望值。

## 学习目标

- 比较 `-refresh=false`、`-refresh-only` 与普通 plan 的数据流和副作用；
- 判断差异发生在配置、state 还是远端 API，并选择正确的恢复动作；
- 在不替换 instance 的前提下修复 tag drift，并证明最终 plan 归零。

## 考纲定位

- **1b / 1c / 1e**：Plan modes、refresh、drift reconciliation 与 state
- **5d**：Troubleshoot provider/runtime differences

## 开始前

```powershell
Set-Location .\new-challenges-4\challenge-89
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

所有 AWS CLI 命令必须保留 LocalStack endpoint。不要在真实 AWS 上制造漂移。

## 任务

### Task 1：部署并记录干净基线

工作目录：`new-challenges-4/challenge-89`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
$instanceId = terraform output -json instance_contract | ConvertFrom-Json | Select-Object -ExpandProperty id
terraform state show aws_instance.workload
terraform plan -detailed-exitcode
$LASTEXITCODE
```

退出码必须是 `0`。基线 Owner 为 `platform-team`，Release 为 `v1`，记下的 ID 后续不能
改变。

### Task 2：从 Terraform 之外注入 Tag Drift

```powershell
aws --endpoint-url=http://localhost:4566 ec2 create-tags `
  --resources $instanceId `
  --tags Key=Owner,Value=incident-team Key=Incident,Value=INC-89

aws --endpoint-url=http://localhost:4566 ec2 describe-tags `
  --filters "Name=resource-id,Values=$instanceId" `
  --query 'Tags[].[Key,Value]'
```

API 必须显示 Owner 已变为 `incident-team`，并出现配置中没有的 `Incident=INC-89`。
此时 Terraform state 仍是旧快照。

### Task 3：证明 `-refresh=false` 会看漏漂移

保持 HCL 不变：

```powershell
terraform plan -refresh=false -detailed-exitcode
$LASTEXITCODE
terraform output -json instance_contract
```

退出码预期为 `0`，output 仍显示旧 Owner，且看不到 Incident。这个“无变更”不是远端已经
合规，而是本次 plan 被明确禁止 refresh。不要 apply 这种盲计划。

### Task 4：用 Refresh-only 只更新 State 认知

```powershell
terraform plan -refresh-only '-out=drift.tfplan'
terraform show drift.tfplan
terraform apply drift.tfplan
terraform output -json instance_contract
terraform state show aws_instance.workload
```

计划应报告对象在 Terraform 之外发生变化；apply 只把远端现实记录进 state/output，不能
调用 EC2 把 Owner 改回去。再用 API 验证 `incident-team` 与 `INC-89` 仍然存在。

### Task 5：用普通 Saved Plan 恢复配置意图

```powershell
terraform plan '-out=repair.tfplan'
terraform show repair.tfplan
terraform apply repair.tfplan
```

普通 plan 应对同一 `aws_instance.workload` 做原地 tag update：Owner 恢复
`platform-team`，Incident 被移除。不能通过 `ignore_changes` 接受漂移，也不能替换实例。

### Task 6：从 State 与 API 完成最终验收

```powershell
$afterId = terraform output -json instance_contract | ConvertFrom-Json | Select-Object -ExpandProperty id
$afterId -eq $instanceId
terraform plan -detailed-exitcode
$LASTEXITCODE
aws --endpoint-url=http://localhost:4566 ec2 describe-tags `
  --filters "Name=resource-id,Values=$instanceId" `
  --query 'Tags[].[Key,Value]'
```

ID 比较必须为 `True`，plan 退出码为 `0`；API 中 Owner/Release 回到配置值且没有 Incident。

## 清理

```powershell
terraform destroy -auto-approve
terraform state list
Remove-Item .\drift.tfplan,.\repair.tfplan -Force -ErrorAction SilentlyContinue
```

## Terraform 1.6 边界

本题使用 Terraform 1.6 的 `-refresh=false` 与 `-refresh-only` planning mode。不要使用
provider mocks、override、手工 state JSON、state push/rm、`ignore_changes` 或脚本。
