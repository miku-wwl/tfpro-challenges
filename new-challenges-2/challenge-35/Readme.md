# Challenge 35：真实 ASG 的容量合同与 Lifecycle

本题在 LocalStack Ultimate 中创建真实的 `aws_autoscaling_group`，再用一次受控的
desired capacity 变更练习 plan 审阅与 `ignore_changes`。这里的“真实”表示 Terraform
通过 AWS provider 管理 Auto Scaling 资源，并且可以从 LocalStack Auto Scaling API
查询；LocalStack 中的 EC2 仍是本地模拟资源。

## 官方考试目标

- **1e**：Manage resource state, including reconciling resource drift
- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types

同时复习类型化输入、资源属性输出、plan 审阅和 state/API 交叉验证。兼容 Terraform
`>= 1.6.0, < 2.0.0`，AWS provider 固定为 `5.80.0`。

## 开始之前

本题要求已启动并激活 LocalStack Ultimate，且 `us-east-1` 的默认 VPC 与
`us-east-1a` 默认子网可用。先进入目录并设置测试凭据：

```powershell
Set-Location .\new-challenges-2\challenge-35
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

aws --endpoint-url=http://localhost:4566 sts get-caller-identity
aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --max-records 10
```

第二条命令能返回 `AutoScalingGroups` 数组即可；数组开始时为空是正常的。

## Starter 状态

Starter 已经提供：

- 类型化变量 `asg_contract`，初值 min/desired/max 为 `1/1/2`；
- `tfpro-c35-launch-template` Launch Template；
- `tfpro-c35-capacity` Auto Scaling Group；
- 默认 `us-east-1a` 子网查询；
- EC2 health check、300 秒 grace period 与 `2m` capacity waiter；
- `starter_capacity_contract` 输出；
- 尚未添加变量 validation，也尚未为 ASG 的 desired capacity 添加 lifecycle rule。

整个 challenge 只有 `Readme.md` 与 `challenge-35.tf` 两个源文件。不要添加脚本、
评分器或其他 Terraform 源文件。

## Task 1：部署真实 ASG 基线

先格式化、验证并保存基线计划。必须先读计划，再 apply 同一个计划文件：

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform show baseline.tfplan
terraform apply baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
```

检查 Terraform 和 LocalStack 是否描述同一个 ASG：

```powershell
terraform output starter_capacity_contract
terraform state show aws_autoscaling_group.capacity

aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names tfpro-c35-capacity `
  --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,LaunchTemplate:LaunchTemplate,Subnets:VPCZoneIdentifier,Instances:Instances[].{Id:InstanceId,Health:HealthStatus,State:LifecycleState}}'
```

预期只返回一个目标组，容量为 `1/1/2`，至少一个模拟实例为 `Healthy/InService`，并且
Launch Template ID 与 subnet ID 能和 Terraform state 对上。

## Task 2：为容量不变量添加 Validation

给 `asg_contract` 添加一条或多条 validation，至少保证：

- `min_size >= 0`；
- `max_size >= 1`；
- `min_size <= desired_capacity <= max_size`。

先用无效输入验证失败路径：

```powershell
terraform plan '-var=asg_contract={min_size=2,desired_capacity=1,max_size=3}'
```

预期在修改资源前失败，错误信息应清楚说明 desired capacity 必须位于 min 与 max
之间。然后验证默认合同仍然稳定：

```powershell
terraform fmt
terraform validate
terraform plan
```

预期 `No changes`。

## Task 3：发布运行时合同

把 `starter_capacity_contract` 重构为 `asg_runtime_contract`，并增加
`contract_version = "1.0"`。最终输出至少包含：

- ASG 的 name 与 ARN；
- Launch Template 的 ID、name 与 latest version；
- subnet ID；
- ASG 资源返回的 min、desired 与 max；
- `runtime = "aws_autoscaling_group"`。

容量值必须引用 `aws_autoscaling_group.capacity` 的属性，而不是直接复制变量输入。
这样后续才能观察配置、state 与远端对象之间的关系。

```powershell
terraform apply -auto-approve
terraform output asg_runtime_contract
terraform plan
```

应用只应更新输出；最终计划应为 `No changes`。

## Task 4：制造并观察真实 Desired Capacity Drift

不要修改 Terraform 配置。用 Auto Scaling API 把远端 desired capacity 从 `1` 改成 `2`：

```powershell
aws --endpoint-url=http://localhost:4566 autoscaling update-auto-scaling-group `
  --auto-scaling-group-name tfpro-c35-capacity `
  --desired-capacity 2

aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names tfpro-c35-capacity `
  --query 'AutoScalingGroups[].{Desired:DesiredCapacity,Instances:Instances[].{Id:InstanceId,Health:HealthStatus,State:LifecycleState}}'

terraform plan '-out=desired-capacity.tfplan'
terraform show desired-capacity.tfplan
```

计划应显示 Terraform 准备把 `aws_autoscaling_group.capacity.desired_capacity` 从远端的
`2` 改回配置声明的 `1`；Launch Template、subnet、min 与 max 不应变化。
不要 apply 这个计划：

```powershell
Remove-Item -LiteralPath .\desired-capacity.tfplan
```

## Task 5：把 Desired Capacity 交给外部系统

在 `aws_autoscaling_group.capacity` 上添加 lifecycle，只忽略 `desired_capacity`。不要忽略
整个资源，也不要把 min/max 加入忽略列表。先用 refresh-only 接受远端容量进入 state，再确认
普通计划不再争夺它：

```powershell
terraform fmt
terraform validate
terraform apply -refresh-only -auto-approve
terraform plan
terraform state show aws_autoscaling_group.capacity

aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names tfpro-c35-capacity `
  --query 'AutoScalingGroups[].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize}'
```

预期 plan 为 `No changes`：配置仍声明 desired capacity `1`，但 state 与 API 中的值都是
外部系统设置的 `2`。这是因为 `ignore_changes` 在更新阶段不再用配置中的该属性生成差异；
创建新资源时，该属性仍会参与创建。

与结对 AI 讨论：真实系统中，只有在 Application Auto Scaling、策略或运维平台确实
拥有 desired capacity 时才适合这样划分所有权。否则它会隐藏误改，Terraform 也不会
自动把远端值纠正回配置值。

## Task 6：用 State 与 API 验收并销毁

先保存资源标识，再分别检查 ASG 与 Launch Template：

```powershell
$contract = terraform output -json asg_runtime_contract | ConvertFrom-Json
$asgName = $contract.autoscaling_group.name
$launchTemplateId = $contract.launch_template.id

terraform state list

aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $asgName `
  --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,LaunchTemplate:LaunchTemplate,Subnets:VPCZoneIdentifier,Instances:Instances[].InstanceId}'

aws --endpoint-url=http://localhost:4566 ec2 describe-launch-templates `
  --launch-template-ids $launchTemplateId

terraform plan
```

state 中的托管资源应包含真实 `aws_autoscaling_group.capacity` 与
`aws_launch_template.capacity`，不能出现 `terraform_data`。data sources 也可能
列在 state 中。最终 plan 应为 `No changes`。

销毁并验证远端对象已删除：

```powershell
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $asgName `
  --query 'AutoScalingGroups'

aws --endpoint-url=http://localhost:4566 ec2 describe-launch-templates `
  --launch-template-ids $launchTemplateId
```

`terraform state list` 应为空，ASG 查询应返回空数组；Launch Template 查询可能返回空数组，
也可能报告未找到。最后删除运行产物，使目录恢复为最初的两个源文件：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

## LocalStack 提醒

- 按本仓实验约定使用 LocalStack Ultimate；本题会实际调用 EC2 与 Auto Scaling API。
- LocalStack 官方当前标注 Auto Scaling 不支持 persistence。练习过程中不要重启
  LocalStack，否则远端 ASG 可能消失而 Terraform state 仍保留旧记录。
- 本题保留 `2m` capacity waiter，要求 Ultimate 返回至少一个 `Healthy/InService` 模拟实例；
  不要用 `wait_for_capacity_timeout = "0"` 隐藏容量创建失败。
- 不要用脚本、第三方 provider 或 `terraform_data` 伪造 ASG 行为。
