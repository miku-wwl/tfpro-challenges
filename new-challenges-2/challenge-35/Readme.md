# Challenge 35：用容量替身练习 ASG 合同与 Lifecycle

本题保留 Auto Scaling Group 的 schema、容量不变量和 lifecycle 推理，但不会向
LocalStack Community 提交 `aws_autoscaling_group`。运行时用一个明确标注的
`terraform_data.capacity` 表示 desired capacity，做法与 Challenge 3.5 相同。

## 官方考试目标

- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types

同时复习类型化输入、plan 审阅与 state 检查。AWS 部分只创建官方学习资源中的
`aws_launch_template`；ASG 合同本身由 Terraform 核心资源模拟。兼容 Terraform
`>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-35
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 包含：

- `tfpro-c35-capacity` Launch Template；
- 类型化 `asg_contract`，初值 min/desired/max 为 1/1/2；
- 一个保存边界的 `terraform_data.bounds`；
- 一个 input 为 desired capacity 的 `terraform_data.capacity`；
- 没有 `aws_autoscaling_group`，也没有 lifecycle rule。

## Task 1：部署容量为 1 的基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
terraform output starter_capacity_contract
terraform state show terraform_data.capacity
```

state 中 `input` 与 `output` 都应为 `1`。

## Task 2：把 ASG 容量不变量写成 Validation

为 `asg_contract` 添加 validation，至少保证：

- min 不小于 0；
- max 不小于 1；
- `min_size <= desired_capacity <= max_size`。

```powershell
terraform plan '-var=asg_contract={min_size=2,desired_capacity=1,max_size=3}'
```

预期在 provider 调用前失败，并说明 desired 不能小于 min。默认合同应继续
`terraform plan` 为 `No changes`。

## Task 3：发布 ASG-shaped 合同

新增 `asg_schema_contract` 输出，包含：

- contract version；
- Launch Template ID/name/latest version；
- min、desired、max；
- 一个明确的 `runtime = "terraform_data"` 标记；
- `autoscaling_applied = false`。

```powershell
terraform apply -auto-approve
terraform output asg_schema_contract
```

输出结构应引用现有资源和变量，不能暗示 LocalStack 已创建真实 ASG。

## Task 4：先观察 Desired Capacity Drift

把默认 `desired_capacity` 从 `1` 改为 `2`，暂时不要加 lifecycle：

```powershell
terraform plan '-out=drift.tfplan'
terraform show drift.tfplan
```

计划应只更新 `terraform_data.capacity` 及依赖它的输出；Launch Template 与 bounds
不应变化。不要 apply，删除计划：

```powershell
Remove-Item -LiteralPath .\drift.tfplan
```

## Task 5：忽略替身 Input 的变化

在 `terraform_data.capacity` 添加 lifecycle，让 Terraform 忽略 `input` 变化。注意
`terraform_data` 只有一个顶层 `input` 属性，因此这个 surrogate 会忽略整个 input；
不要把它错误描述成真实 ASG provider 的细粒度 schema。

```powershell
terraform plan
terraform state show terraform_data.capacity
terraform output asg_schema_contract
```

预期 `No changes`，state 的 capacity 仍为初始值 `1`，尽管配置默认值已写成 `2`。说明
配置、state 与输出分别引用哪个值，并与结对 AI 讨论 ignore_changes 的维护风险。

## Task 6：从 State 与 EC2 API 验收并清理

```powershell
$contract = terraform output -json asg_schema_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 ec2 describe-launch-templates `
  --launch-template-ids $contract.launch_template.id
terraform state list
terraform plan
terraform destroy -auto-approve
```

state 只能包含 Launch Template 和两个 terraform_data 对象，不能出现
`aws_autoscaling_group`。API 返回的 template 应与合同一致。销毁后 API 不应再找到它，
state 应为空。删除运行产物，恢复两个源文件。

## LocalStack 提醒

- LocalStack Community 当前不提供本题需要的完整 Auto Scaling runtime，因此真实 ASG
  明确不 apply。
- `terraform_data` 只模拟容量值的 Terraform lifecycle 行为，不模拟实例扩缩容。
- 不要用第三方 provider、脚本或伪造的 AWS ASG API 响应补足功能。
