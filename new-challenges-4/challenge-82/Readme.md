# Challenge 82：把复杂块设备目录编译成 Launch Template 动态块

这个练习从一份只有单个、字面量 root volume 的 Launch Template 开始。你会先把相同语义
表达成类型化 catalog，再用 `dynamic` block 生成嵌套的 `block_device_mappings`。完成迁移
时必须先得到零变更计划，然后才扩展第二块盘；这样可以把“结构重构”和“真实发布变更”
分开审阅。

## 官方考试目标

- **2a**：Use language features to validate configuration
- **2c**：Compute and interpolate data using HCL functions
- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types
- 辅助使用 **1b / 1c**：保存、审阅并应用计划

使用官方 AWS 学习资源中的 `data.aws_ami` 与 `aws_launch_template`。本题固定兼容
Terraform `~> 1.6.0`。

## Starter 状态

工作目录：

```powershell
Set-Location .\new-challenges-4\challenge-82
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 已经可以直接 apply：

- AWS provider `5.80.0` 的 EC2/STS endpoint 指向 LocalStack；
- AMI 由 data source 查询；
- `aws_launch_template.release` 含一块字面量 `/dev/sda1` gp3 root volume；
- 还没有复杂变量、validation、local catalog 或 dynamic block。

目录最终只能保留 `Readme.md` 和 `challenge-82.tf`。

## Task 1：部署字面量 v1 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=v1.tfplan'
terraform show v1.tfplan
terraform apply v1.tfplan
terraform output starter_launch_template
Remove-Item -LiteralPath .\v1.tfplan
```

预期创建 1 个 Launch Template，`default_version` 与 `latest_version` 都为 `1`。

用 API 核验 root volume：

```powershell
$ltName = (terraform output -json starter_launch_template | ConvertFrom-Json).name
aws --endpoint-url=http://localhost:4566 ec2 describe-launch-template-versions `
  --launch-template-name $ltName `
  --versions '$Latest' `
  --query 'LaunchTemplateVersions[].LaunchTemplateData.BlockDeviceMappings'
```

## Task 2：声明类型化块设备 Catalog

添加 `variable "block_devices"`，类型为 map of objects；map key 就是 Linux device name。
每个 value 至少包含：

- `volume_type`、`volume_size`；
- `encrypted`、`delete_on_termination`；
- 可选的 `iops` 与 `throughput`。

先只放入 `/dev/sda1`，值必须和 starter 的字面量 root volume 完全相同。加入 validation：

1. device key 必须以 `/dev/` 开头；
2. volume size 必须大于 0；
3. 本练习只接受 `gp3`；
4. 若给出 IOPS/throughput，它们必须分别至少为 3000/125。

此时还不要改资源：

```powershell
terraform fmt
terraform validate
terraform plan
```

预期 `No changes`。

验证失败路径：

```powershell
terraform plan '-var=block_devices={\"/dev/sda1\"={volume_type=\"gp3\",volume_size=0,encrypted=true,delete_on_termination=true,iops=3000,throughput=125}}'
```

plan 必须被 variable validation 挡住，不能调用 CreateLaunchTemplateVersion。失败后继续
使用默认值。

## Task 3：规范化 Optional 与 Provider Schema

添加 `local.block_devices`，逐项生成 provider 所需的结构。注意 AWS provider `5.80.0`
在 Launch Template 的 EBS block 中把 `encrypted` 与 `delete_on_termination` 定义为字符串，
所以在 local 或 dynamic content 中显式使用 `tostring(...)`；未提供的 optional 数值保持
`null`，不要编造值。

添加临时输出 `normalized_block_devices` 并运行：

```powershell
terraform console
```

在 console 中检查：

```hcl
local.block_devices
keys(local.block_devices)
```

退出 console 后：

```powershell
terraform plan
```

预期仍然 `No changes`。

## Task 4：用 Dynamic Block 做零变更迁移

删除资源中唯一的字面量 `block_device_mappings`，改为一个
`dynamic "block_device_mappings"`：

- `for_each` 使用规范化 map；
- `device_name` 使用当前 element 的 key；
- 嵌套 `ebs` 完整映射六个 catalog 字段；
- optional `iops`/`throughput` 保持 `null` 或对应值。

```powershell
terraform fmt -check
terraform validate
terraform plan '-out=refactor.tfplan'
terraform show refactor.tfplan
```

预期严格 `No changes`。如果计划创建新版本，先修正语义差异，不要 apply。确认零变更后：

```powershell
terraform apply refactor.tfplan
Remove-Item -LiteralPath .\refactor.tfplan
```

## Task 5：只通过 Catalog 增加数据盘

在默认 catalog 中加入 `/dev/sdf`：

- `volume_type = "gp3"`；
- `volume_size = 20`；
- `encrypted = true`；
- `delete_on_termination = true`；
- 显式设置合法的 IOPS 与 throughput。

不要复制第二个 resource 或 dynamic block。

```powershell
terraform plan '-out=v2.tfplan'
terraform show v2.tfplan
terraform apply v2.tfplan
Remove-Item -LiteralPath .\v2.tfplan
```

预期是同一个 Launch Template 的原地 update，LocalStack 中出现 version 2；不是第二个
Launch Template，也不是 destroy/create。

## Task 6：发布版本化合同并清理

把输出整理为 `launch_template_contract`，至少包含：

- template ID/name；
- AMI ID；
- default/latest version；
- 按 device name 排序的规范化块设备列表。

```powershell
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output launch_template_contract

$ltName = (terraform output -json launch_template_contract | ConvertFrom-Json).name
aws --endpoint-url=http://localhost:4566 ec2 describe-launch-template-versions `
  --launch-template-name $ltName `
  --query 'LaunchTemplateVersions[].{Version:VersionNumber,Default:DefaultVersion,Devices:LaunchTemplateData.BlockDeviceMappings}'

terraform plan
terraform destroy -auto-approve
```

最终 plan 必须为 `No changes`；API 的最新版本必须包含 `/dev/sda1` 与 `/dev/sdf`。
销毁后清理 `.terraform`、lockfile、state 和临时 plan，恢复 starter 文件集合。

## LocalStack 提醒

- Launch Template 会被模拟，但不会真正挂载 EBS volume。
- LocalStack 对部分 EC2 默认值的回读可能比 AWS 简化；以 provider state 与 API 返回的
  device name、size、type 为主要验收字段。
- 不要加入 `aws_autoscaling_group`。当前 Community LocalStack 的 Auto Scaling API需要
  额外许可，而且本题考点只需要 Launch Template。
