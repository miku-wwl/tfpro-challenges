# Challenge 82：动态块设备目录、Launch Template 版本与真实 ASG

本题从一个已经可运行的发布基线开始：类型化的块设备 catalog 经过 local 规范化，
再由 `dynamic` block 编译成 Launch Template；真实 Auto Scaling Group 消费该模板的
最新版本。你会先从 Terraform state 与 LocalStack API 证明基线，再依次练习 variable
validation、optional 默认值的零变更重构、数据驱动的模板版本更新，以及 ASG 的版本消费关系。

这里的“真实 ASG”表示 Terraform 通过 AWS provider 管理
`aws_autoscaling_group`，LocalStack Auto Scaling API 中也能查询到组与它管理的模拟 EC2
instances。

## 官方考试目标

- **1b / 1c**：生成、审阅并应用执行计划
- **1e**：管理 state，并识别配置、state 与远端对象之间的关系
- **2a**：使用语言特性验证配置
- **2b**：使用 data sources 查询 provider
- **2c**：使用 HCL 表达式与函数计算数据
- **2d**：使用 meta-arguments，包括 `for_each`、`dynamic` 与 lifecycle
- **2e**：配置复杂 input variables 与 outputs

本题只使用 Terraform Professional 考试资源清单中的 `data.aws_ami`、
`data.aws_subnet`、`aws_launch_template` 与 `aws_autoscaling_group`。兼容 Terraform
`>= 1.6.0, < 2.0.0`，AWS provider 固定为 `5.80.0`。

## 开始之前

启动并激活 LocalStack Ultimate，然后进入目录并设置 AWS CLI 测试凭据：

```powershell
Set-Location .\new-challenges-4\challenge-82
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

aws --endpoint-url=http://localhost:4566 sts get-caller-identity
aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --max-records 10
```

第二条命令能返回 `AutoScalingGroups` 数组即可；开始时数组为空是正常的。

## Starter 状态

先只阅读 `challenge-82.tf` 与 `variable.tf`，画出下面的依赖链：

```text
block_devices variable
        ↓
local.block_devices
        ↓
aws_launch_template.release ──→ aws_autoscaling_group.release
        ↑                              ↑
data.aws_ami.selected          data.aws_subnet.selected
```

Starter 已提供：

- `block_devices`：包含 `/dev/sda1` 与 `/dev/sdf` 的 map of objects；
- key、size、volume type、IOPS 与 throughput validations；
- 把 bool 规范化为 provider schema 所需字符串的 local；
- 生成嵌套 `block_device_mappings` 的 `dynamic` block；
- 真实 ASG `tfpro-c82-release`，min/desired/max 为 `1/1/2`；
- EC2 health check、300 秒 grace period 与 `2m` capacity waiter；
- 同时发布 Launch Template、块设备和 ASG 属性的 `launch_template_contract` output。

目录只保留这两个 Terraform 源文件与 `Readme.md`；不要添加脚本、评分器或 provider
替身。完成练习后要把两个 `.tf` 文件恢复为 starter 内容。

## Task 1：部署并交叉验证真实发布基线

先生成并阅读保存的计划，再应用同一个 plan 文件：

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c82-baseline.tfplan'
terraform show .\c82-baseline.tfplan
terraform apply .\c82-baseline.tfplan
Remove-Item -LiteralPath .\c82-baseline.tfplan
```

计划应创建 1 个 Launch Template 与 1 个真实 ASG；ASG 启动的 instance 不会在 state
中拥有单独的 `aws_instance` address。用 output、state 和两个 API 交叉检查：

```powershell
$contract = terraform output -json launch_template_contract | ConvertFrom-Json

terraform state list
terraform state show aws_launch_template.release
terraform state show aws_autoscaling_group.release

aws --endpoint-url=http://localhost:4566 ec2 describe-launch-template-versions `
  --launch-template-name $contract.name `
  --versions '$Latest' `
  --query 'LaunchTemplateVersions[].{Version:VersionNumber,Default:DefaultVersion,Devices:LaunchTemplateData.BlockDeviceMappings}'

aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $contract.autoscaling_group.name `
  --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,LT:LaunchTemplate,Instances:Instances[].{Id:InstanceId,Health:HealthStatus,State:LifecycleState}}'
```

预期块设备只有 `/dev/sda1` 与 `/dev/sdf`；ASG 容量为 `1/1/2`，并且至少一个模拟
instance 为 `Healthy/InService`。ASG 返回的 Launch Template ID/version 应与 output 一致。

## Task 2：补强 Catalog 的结构不变量

先运行一个失败用例，证明现有 key validation 会在 provider 调用前阻止错误输入：

```powershell
terraform plan '-var=block_devices={\"sda1\"={volume_type=\"gp3\",volume_size=8,encrypted=true,delete_on_termination=true,iops=3000,throughput=125}}'
```

错误消息应说明 device key 必须以 `/dev/` 开头。接着给 `block_devices` 再添加一条
validation，要求 catalog 必须包含 root device `/dev/sda1`。不要把这个规则写进 resource
precondition，因为它约束的是 variable 本身。

用只有数据盘的输入验证失败路径：

```powershell
terraform plan '-var=block_devices={\"/dev/sdf\"={volume_type=\"gp3\",volume_size=20,encrypted=true,delete_on_termination=true,iops=3000,throughput=125}}'
```

然后验证默认输入仍是零变更：

```powershell
terraform fmt
terraform validate
terraform plan
```

默认计划必须为 `No changes`。和结对 AI 解释为什么 validation condition 可以使用
`contains(keys(var.block_devices), "/dev/sda1")`，以及为什么错误信息应描述调用者能修复的约束。

## Task 3：用 Optional 默认值做零变更重构

当前 `iops` 与 `throughput` 是没有默认值的 optional attributes，而两个默认设备又重复写了
`3000` 与 `125`。把类型约束重构为：

```hcl
iops       = optional(number, 3000)
throughput = optional(number, 125)
```

只从 `/dev/sda1` 的默认对象中删除显式 `iops` 与 `throughput`；暂时保留 `/dev/sdf` 的显式值。
先用 console 确认 Terraform 已注入默认值：

```powershell
terraform console
```

在 console 中分别求值：

```hcl
var.block_devices["/dev/sda1"]
local.block_devices["/dev/sda1"]
```

退出 console 后保存并审阅计划：

```powershell
terraform fmt -check
terraform validate
terraform plan '-out=c82-refactor.tfplan'
terraform show .\c82-refactor.tfplan
```

这里必须严格 `No changes`。如果计划准备创建新的 Launch Template version，说明重构改变了
最终 provider 输入；先修正差异，不要 apply。确认零变更后删除 plan 文件：

```powershell
Remove-Item -LiteralPath .\c82-refactor.tfplan
```

## Task 4：只通过 Catalog 增加第三块盘

在 `block_devices` 默认 map 中增加 `/dev/sdg`：

- `volume_type = "gp3"`；
- `volume_size = 12`；
- `encrypted = true`；
- `delete_on_termination = true`；
- 故意省略 IOPS 与 throughput，让 Task 3 的 optional 默认值生效。

不要复制第二个 resource 或 `dynamic` block。生成并审阅计划：

```powershell
terraform plan '-out=c82-third-disk.tfplan'
terraform show .\c82-third-disk.tfplan
```

计划应原地更新同一个 Launch Template，创建它的新版本，并让 ASG 的
`launch_template.version` 消费新的 `latest_version`；不应替换 ASG。确认后应用：

```powershell
terraform apply .\c82-third-disk.tfplan
Remove-Item -LiteralPath .\c82-third-disk.tfplan
$contract = terraform output -json launch_template_contract | ConvertFrom-Json

aws --endpoint-url=http://localhost:4566 ec2 describe-launch-template-versions `
  --launch-template-name $contract.name `
  --versions '$Latest' `
  --query 'LaunchTemplateVersions[].{Version:VersionNumber,Devices:LaunchTemplateData.BlockDeviceMappings}'

aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $contract.autoscaling_group.name `
  --query 'AutoScalingGroups[].LaunchTemplate'
```

最新模板应包含三个 device names，`/dev/sdg` 的 IOPS/throughput 应为 `3000/125`；ASG 引用的
version 应等于 `contract.latest_version`。最后运行 `terraform plan`，预期 `No changes`。

## Task 5：区分模板版本更新与 Instance 刷新

只把 `/dev/sdf` 的 `volume_size` 从 `20` 改为 `24`。保存计划并逐项回答：

1. 哪个 resource address 原地更新？
2. Launch Template 的 `latest_version` 为什么增加？
3. ASG 为什么只需要更新它引用的 version，而不是被替换？
4. 为什么更新 ASG 的 Launch Template version 不等于自动替换已经运行的 instances？

```powershell
terraform plan '-out=c82-volume-update.tfplan'
terraform show .\c82-volume-update.tfplan
terraform apply .\c82-volume-update.tfplan
Remove-Item -LiteralPath .\c82-volume-update.tfplan

$contract = terraform output -json launch_template_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $contract.autoscaling_group.name `
  --query 'AutoScalingGroups[].{LT:LaunchTemplate,Instances:Instances[].InstanceId}'

terraform plan
```

最后一个计划必须为 `No changes`。本题不添加 instance refresh、mixed instances policy、
scaling policy、load balancer 或 warm pool；这些不是本 lab 的考试目标。

## Task 6：State/API 双向验收并销毁

先保存远端标识，再核对 state 与 API：

```powershell
$contract = terraform output -json launch_template_contract | ConvertFrom-Json
$asgName = $contract.autoscaling_group.name
$launchTemplateId = $contract.id

terraform state list
terraform output launch_template_contract

aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $asgName `
  --query 'AutoScalingGroups[].{Name:AutoScalingGroupName,Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,LT:LaunchTemplate,Instances:Instances[].InstanceId}'

aws --endpoint-url=http://localhost:4566 ec2 describe-launch-template-versions `
  --launch-template-id $launchTemplateId `
  --query 'LaunchTemplateVersions[].{Version:VersionNumber,Default:DefaultVersion,Devices:LaunchTemplateData.BlockDeviceMappings}'

terraform plan
```

最终 plan 应为 `No changes`。销毁并确认远端对象消失：

```powershell
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $asgName `
  --query 'AutoScalingGroups'

aws --endpoint-url=http://localhost:4566 ec2 describe-launch-templates `
  --launch-template-ids $launchTemplateId
```

state 与 ASG 数组应为空；Launch Template 查询可能返回空数组，也可能报告 not found。把两个
`.tf` 文件恢复为 starter 内容，再删除运行产物：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

目录最终应只剩 `Readme.md`、`challenge-82.tf` 与 `variable.tf`。

## LocalStack 提醒

- 本题按仓库约定使用 LocalStack Ultimate，并实际调用 EC2 与 Auto Scaling API。
- LocalStack 当前不持久化 Auto Scaling state；练习过程中不要重启 LocalStack，否则远端 ASG
  可能消失而 Terraform state 仍保留旧记录。
- 保留 `2m` capacity waiter；不要把它设为 `"0"` 来掩盖实例没有进入服务的问题。
- LocalStack 使用模拟 EC2 instance，不会真正挂载 EBS volumes，也不等同于 AWS 的生产健康检查、
  CloudWatch 指标或扩缩容时序。
- LocalStack 会把 Launch Template 顶层 tags 同时回读为 provider 的等价
  `tag_specifications`。starter 只忽略这个模拟器规范化字段，不会忽略 AMI、块设备或版本变化。
