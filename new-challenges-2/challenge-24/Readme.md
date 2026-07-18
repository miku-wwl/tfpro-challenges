# Challenge 24：用 `-replace` 做一次有证据的 EC2 受控替换

一台 EC2 instance 的配置没有变化，但运行团队要求轮换其远端身份。你需要先保存替换计划，
证明计划尚未执行时旧实例仍受管，再应用同一份计划并用新旧 instance ID 证明发生了替换。
不能通过改 AMI、改 instance type 或手工删实例来制造替换。

## 官方考试目标

- **1b**：Generate an execution plan using `terraform plan` and its options
- **1c**：Apply configuration changes using `terraform apply` and its options
- **1e**：Manage resource state over time

本题使用官方 AWS 学习资源中的 `data.aws_ami` 与 `aws_instance`。配置兼容 Terraform
`>= 1.6.0, < 2.0.0`，`-replace` 是 Terraform 1.6 范围内的 CLI 能力。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-24
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 中只有两个源文件，并已包含：

- AWS provider `5.80.0`，EC2 指向 LocalStack；
- 按名称、架构与状态选择最新 AMI 的 data source；
- `aws_instance.exercise`，标签名为 `tfpro-c24-replace`；
- 同时暴露稳定属性与 provider-assigned ID 的 `instance_contract`。

LocalStack EC2 不启动真实虚拟机。本题以 API 对象和 Terraform state 为准，不以 SSH 为准。

## Task 1：部署未替换的基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply .\baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
terraform plan
```

第一次计划应创建 1 台 instance；随后 plan 应为 `No changes`。保存旧合同：

```powershell
$before = terraform output -json instance_contract | ConvertFrom-Json
$before
terraform state show aws_instance.exercise
```

`$before.id` 应是非空 LocalStack instance ID。

## Task 2：从 AWS API 核对旧身份

```powershell
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $before.id `
  --query 'Reservations[].Instances[].{Id:InstanceId,Image:ImageId,Type:InstanceType,State:State.Name}'
```

API 的 Id、Image 和 Type 应与 `$before` 一致。此时不要编辑 `challenge-24.tf`。

## Task 3：保存并审阅显式替换计划

```powershell
terraform plan '-replace=aws_instance.exercise' '-out=replace.tfplan'
terraform show -no-color .\replace.tfplan
terraform output -json instance_contract | ConvertFrom-Json
```

计划中 `aws_instance.exercise` 应标记为 replacement，摘要通常为 1 add、1 destroy；具体先后
顺序以计划符号为准。仅生成计划不会修改 state，当前输出的 ID 仍应等于 `$before.id`。

不要重新运行 plan 覆盖 `replace.tfplan`，下一步必须应用刚审阅的同一文件。

## Task 4：应用同一计划并比较新旧 ID

```powershell
terraform apply .\replace.tfplan
Remove-Item -LiteralPath .\replace.tfplan
$after = terraform output -json instance_contract | ConvertFrom-Json
$after
$before.id -ne $after.id
```

最后一条表达式必须为 `True`，而 AMI 与 instance type 应保持不变。再核对新对象：

```powershell
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $after.id `
  --query 'Reservations[].Instances[].{Id:InstanceId,Image:ImageId,Type:InstanceType,State:State.Name}'
terraform state show aws_instance.exercise
```

state 地址没有变化，远端 ID 已变化；这正是“同一资源地址下替换远端对象”。

## Task 5：证明替换意图不写回源配置

```powershell
terraform plan
terraform plan '-replace=aws_instance.exercise' '-out=discarded.tfplan'
terraform show -no-color .\discarded.tfplan
Remove-Item -LiteralPath .\discarded.tfplan
terraform plan
```

第一和最后一次普通 plan 都应显示 `No changes`；中间只有带 `-replace` 的计划要求再次替换。
删除未应用的 plan 后，不会在配置或 state 中留下待执行动作。

## Task 6：最终验收并清理

```powershell
terraform output -json instance_contract | ConvertFrom-Json
terraform state list
terraform plan
terraform destroy -auto-approve
terraform state list
```

销毁后 state 应为空。旧 ID 在不同 LocalStack 版本中可能消失，也可能短暂显示为 terminated；
当前 ID 不应再是运行中的受管实例。删除运行产物：

```powershell
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate, .\terraform.tfstate.backup `
  -ErrorAction SilentlyContinue
Get-ChildItem -File -Filter '*.tfplan' | Remove-Item -Force
Get-ChildItem -Force | Select-Object Name
```

最终只应看到 `Readme.md` 和 `challenge-24.tf`。

## LocalStack 提醒

- LocalStack 的 EC2 replacement 只替换 API 模型，不会启动或停机真实 guest。
- 不要把 LocalStack 返回的某个 AMI ID写死；内置 catalog 可能随版本变化。
- `-replace` 比旧式 `terraform taint` 更适合在 plan 中显式审阅替换意图。
