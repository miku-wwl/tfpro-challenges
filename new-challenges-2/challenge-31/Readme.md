# Challenge 31：把块设备目录编译成 Launch Template 动态块

这个练习从一个可以直接部署的 Launch Template 开始。它只有一块字面量 root volume；
你会先把同样的含义表达成类型化 catalog，再用 `dynamic` block 生成嵌套块。迁移阶段
必须保持零变更，之后才加入第二块数据盘，从而把“重构”与“发布变更”分开审阅。

## 官方考试目标

- **2a**：Use language features to validate configuration
- **2c**：Compute and interpolate data using HCL functions
- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types

使用官方 AWS 学习资源中的 `data.aws_ami` 与 `aws_launch_template`。本题兼容
Terraform `>= 1.6.0, < 2.0.0`，AWS provider 固定为 `5.80.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-31
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

目录中只有 `Readme.md` 和 `challenge-31.tf`。Starter 已包含：

- 指向 LocalStack EC2/STS 的 provider；
- 按条件查询 AMI 的 data source；
- 名为 `tfpro-c31-release` 的 Launch Template；
- 一块字面量 `/dev/sda1` gp3 root volume；
- 最小的 `starter_launch_template` 输出。

它还没有复杂变量、规范化 local 或 dynamic block。开始前确认 LocalStack 的 `ec2`
与 `sts` 服务可用，目录中没有旧 state、lockfile 或 plan。

## Task 1：部署字面量基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform show baseline.tfplan
terraform apply baseline.tfplan
terraform output starter_launch_template
Remove-Item -LiteralPath .\baseline.tfplan
```

预期只创建一个 Launch Template，`latest_version` 为 `1`。记录输出中的 name，随后
查询 LocalStack：

```powershell
$ltName = (terraform output -json starter_launch_template | ConvertFrom-Json).name
aws --endpoint-url=http://localhost:4566 ec2 describe-launch-template-versions `
  --launch-template-name $ltName `
  --versions '$Latest' `
  --query 'LaunchTemplateVersions[].LaunchTemplateData.BlockDeviceMappings'
```

API 应只返回 `/dev/sda1`。

## Task 2：声明类型化块设备 Catalog

在 `challenge-31.tf` 中添加 `block_devices` 输入变量。它应是以 device name 为 key
的 map of objects；每个对象包含 `volume_type`、`volume_size`、`encrypted`、
`delete_on_termination`，以及可选的 `iops`、`throughput`。

默认 catalog 此时只能包含 `/dev/sda1`，所有值必须与基线资源完全相同。加入 validation：

1. key 必须以 `/dev/` 开头；
2. size 必须大于 0；
3. 本练习只接受 `gp3`；
4. 给出 IOPS/throughput 时，值分别不得低于 3000/125。

先不要修改资源：

```powershell
terraform fmt
terraform validate
terraform plan
```

预期 `No changes`。然后用一个 size 为 0 的临时 `-var` 覆盖验证失败路径；plan 必须
在调用 AWS API 之前被 variable validation 拒绝。测试后恢复默认输入。

## Task 3：规范化 Optional 与 Provider Schema

创建一个 local，把 catalog 规范化为 dynamic block 将要消费的结构：

- map key 继续作为 device name，不能改成列表下标；
- 未提供的 IOPS/throughput 保持 `null`；
- AWS provider `5.80.0` 对该嵌套块回读的布尔字段按 schema 所需形式处理；
- 不要为缺省 optional 字段编造业务值。

添加临时输出 `normalized_block_devices`，再检查：

```powershell
terraform console
```

在 console 中求值 `local.block_devices` 与 `sort(keys(local.block_devices))`，退出后运行：

```powershell
terraform plan
```

仍应为 `No changes`。

## Task 4：用 Dynamic Block 做零变更迁移

删除字面量 `block_device_mappings`，改为一个同名 dynamic block。`for_each` 必须使用
规范化 map，并在 `content` 中完整映射 device name 与 EBS 字段。

```powershell
terraform fmt -check
terraform validate
terraform plan '-out=refactor.tfplan'
terraform show refactor.tfplan
```

预期严格 `No changes`。若出现新 Launch Template version，先修正语义差异，不要 apply。
确认后：

```powershell
terraform apply refactor.tfplan
Remove-Item -LiteralPath .\refactor.tfplan
```

## Task 5：只通过 Catalog 增加数据盘

向默认 catalog 增加 `/dev/sdf`：gp3、20 GiB、加密、随实例删除，并给出合法 IOPS 与
throughput。不要复制 resource 或 dynamic block。

```powershell
terraform plan '-out=release.tfplan'
terraform show release.tfplan
terraform apply release.tfplan
Remove-Item -LiteralPath .\release.tfplan
terraform plan
```

预期同一个 Launch Template 出现新版本，最后一次 plan 为 `No changes`。

## Task 6：发布合同、双向验收并清理

将输出整理为 `launch_template_contract`，至少包含 template ID/name、AMI ID、
default/latest version，以及按 device name 排序的规范化设备列表。

```powershell
terraform output launch_template_contract
$ltName = (terraform output -json launch_template_contract | ConvertFrom-Json).name
aws --endpoint-url=http://localhost:4566 ec2 describe-launch-template-versions `
  --launch-template-name $ltName `
  --query 'LaunchTemplateVersions[].{Version:VersionNumber,Default:DefaultVersion,Devices:LaunchTemplateData.BlockDeviceMappings}'
terraform state list
terraform destroy -auto-approve
```

最新 API 版本应同时含 `/dev/sda1` 与 `/dev/sdf`。销毁后 `terraform state list` 应为空，
API 不应再找到 `tfpro-c31-release`。删除 `.terraform`、lockfile、state/backup 和临时
plan，使目录恢复为最初两个源文件。

## LocalStack 提醒

- Launch Template 会被模拟，但不会真的挂载 EBS volume。
- 以 device name、size、type 和版本号验收，不依赖真实块设备。
- LocalStack 默认 AMI catalog 可能变化，因此 starter 用过滤条件而不是固定 AMI ID。
