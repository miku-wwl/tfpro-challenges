# Challenge 42：用 For_each 稳定地调用同一个 Local Module 两次

这个练习从 blue/green 两个重复的 S3 resource block 开始。你会把重复逻辑提取到临时
local module，再用一个 module call 加 `for_each` 消费两项类型化 map；稳定 key 必须
让重排保持零变更，并把单项修改限制在对应 module instance。

## 官方考试目标

- **4a**：Create a module
- **4b**：Use a module in configuration
- **2d**：Use meta-arguments in configuration

使用官方 AWS `aws_s3_bucket` 与本地 child module。兼容 Terraform
`>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-42
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

源 TF 已声明 `deployments` map，但用两个几乎相同的根 resource 分别读取 `blue` 与
`green`。没有 module。练习全部在临时 `work` 副本进行。

## Task 1：部署两个重复资源的基线

```powershell
New-Item -ItemType Directory -Path .\work
Copy-Item .\challenge-42.tf .\work\main.tf
Set-Location .\work
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform state list
terraform output starter_deployments
```

state 应含 `aws_s3_bucket.blue` 和 `aws_s3_bucket.green`，API 中有两个不同 bucket。

## Task 2：设计一个可重复使用的 Storage Module

```powershell
New-Item -ItemType Directory -Path .\modules\storage
New-Item -ItemType File -Path .\modules\storage\main.tf
New-Item -ItemType File -Path .\modules\storage\variables.tf
New-Item -ItemType File -Path .\modules\storage\outputs.tf
```

module 应：

- 接收一个包含 bucket name 与 owner 的 object；
- 创建一个 `aws_s3_bucket.this`；
- 固定添加 `ManagedBy = "Terraform"`，并从输入生成 Name/Owner；
- 输出 name、ARN、owner。

不要在 module 内配置 provider block；它继承 root 传入的 AWS provider。

## Task 3：用一个 Module Block 消费两项 Map

删除两个重复 root resource，添加一个 `module "storage"`：

- `source = "./modules/storage"`；
- `for_each = var.deployments`；
- 当前对象来自 `each.value`。

把根输出改为以相同 key 汇总 module contracts。暂不添加 moved block：

```powershell
terraform fmt -recursive
terraform init
terraform validate
terraform plan
```

预期计划把两个根资源替换为 `module.storage["blue"]` 和 `["green"]` 下的资源。不要 apply。

## Task 4：用稳定 Key 映射旧地址

加入两条 moved block：

- `aws_s3_bucket.blue` → `module.storage["blue"].aws_s3_bucket.this`；
- `aws_s3_bucket.green` → `module.storage["green"].aws_s3_bucket.this`。

```powershell
terraform plan '-out=modules.tfplan'
terraform show modules.tfplan
terraform apply modules.tfplan
Remove-Item .\modules.tfplan
terraform state list
```

预期零 bucket destroy/create，state 只改变地址。

## Task 5：验证重排与单 Key 变更

先交换 `deployments` 中两项的书写顺序：

```powershell
terraform plan
```

必须 `No changes`。再只把 `green.owner` 改为 `release-team`：

```powershell
terraform plan '-out=green.tfplan'
terraform show green.tfplan
terraform apply green.tfplan
Remove-Item .\green.tfplan
terraform plan
```

计划只能更新 `module.storage["green"]`。最后临时把 key `green` 改名为 `emerald` 并
plan；应看到旧 key destroy、新 key create。不要 apply，恢复 `green`。

## Task 6：发布汇总合同、API 验收并清理

```powershell
terraform output deployment_contracts
terraform state list
aws --endpoint-url=http://localhost:4566 s3api list-buckets `
  --query "Buckets[?starts_with(Name, 'tfpro-c42-')].Name"
terraform plan
terraform destroy -auto-approve
Set-Location ..
Remove-Item .\work -Recurse -Force
Get-ChildItem -Force
```

输出与 state 应恰好有 blue/green 两个稳定 key；最终 plan 为 `No changes`。销毁后 API
筛选结果为空，源目录只剩两个 starter 文件。

## LocalStack 提醒

- S3 bucket 名是全局标识，但 module instance 地址由 map key 决定，两者不要混为一谈。
- Map 重排不影响 `for_each`；key 重命名则是地址变更。
- module 文件只存在于临时 `work`，清理时整个删除。
