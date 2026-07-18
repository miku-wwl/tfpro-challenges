# Challenge 43：重构 Module Interface，同时保留旧输出合同

这个练习从 scalar inputs、单体 S3 resource 和 legacy `bucket_name` 输出开始。你会先把
resource 移入 module，再把 module 的 scalar interface 重构为 typed object，同时让根
输出向后兼容；最后重命名 module 内资源并用 moved block 保留地址连续性。

## 官方考试目标

- **4c**：Refactor a module and use module versioning
- **4d**：Refactor an existing configuration into modules
- **1e**：Manage resource state, including importing resources and reconciling resource drift

使用官方 AWS `aws_s3_bucket` 与 Terraform `moved` block。兼容 Terraform
`>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-43
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 根模块接收 `bucket_name`、`release_label` 两个 scalar，创建
`tfpro-c43-interface`，并只输出旧合同 `bucket_name`。所有重构在临时 `work` 进行。

## Task 1：部署 Legacy Interface 基线

```powershell
New-Item -ItemType Directory .\work
Copy-Item .\challenge-43.tf .\work\main.tf
Set-Location .\work
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output bucket_name
terraform state list
```

记录 bucket ID 与根资源地址 `aws_s3_bucket.release`。

## Task 2：先提取 Scalar V1 Module

创建 `modules/storage`，module v1 接收与 root 相同的两个 scalar，资源本地名称为
`aws_s3_bucket.this`，输出 `bucket_name`。根模块改为调用 module，但继续保留原
root variables 和 root output。

添加 moved block，把 `aws_s3_bucket.release` 映射到
`module.storage.aws_s3_bucket.this`。

```powershell
New-Item -ItemType Directory .\modules\storage
New-Item -ItemType File .\modules\storage\main.tf
New-Item -ItemType File .\modules\storage\variables.tf
New-Item -ItemType File .\modules\storage\outputs.tf
terraform fmt -recursive
terraform init
terraform validate
terraform plan '-out=extract.tfplan'
terraform show extract.tfplan
```

预期没有 bucket destroy/create。确认后 apply 并删除 plan。

## Task 3：把 Module Input 重构为 Typed Object

将 child module 的两个 scalar inputs 合并为 `storage` object，字段至少含 name、
release_label、force_destroy。root 的旧 variables 暂时保留，并在 module call 中组装
新 object，因此调用者仍可传旧变量。

```powershell
terraform fmt -recursive
terraform validate
terraform plan
```

必须 `No changes`。这是 interface adapter，不是资源发布。

## Task 4：增加新合同但保留 Legacy Output

让 module 新增 `contract` 输出，包含 name、ARN、release label；root 新增
`storage_contract`。原根输出 `bucket_name` 必须继续存在，并从新 contract 派生。

```powershell
terraform plan '-out=outputs.tfplan'
terraform show outputs.tfplan
terraform apply outputs.tfplan
Remove-Item .\outputs.tfplan
terraform output bucket_name
terraform output storage_contract
```

计划只能新增/更新 outputs，不能改 bucket。两个输出中的 name 必须相同。

## Task 5：重命名 Module 内 Resource Address

将 child resource 从 `aws_s3_bucket.this` 重命名为 `aws_s3_bucket.release`，同时在
child module 内添加 moved block，从旧本地地址映射到新地址。

```powershell
terraform fmt -recursive
terraform plan '-out=rename.tfplan'
terraform show rename.tfplan
terraform apply rename.tfplan
Remove-Item .\rename.tfplan
terraform state list
terraform plan
```

state 地址应变为 `module.storage.aws_s3_bucket.release`，bucket ID 不变，最终
`No changes`。

## Task 6：验证兼容合同并清理临时 Module

```powershell
$legacy = terraform output -raw bucket_name
$contract = terraform output -json storage_contract | ConvertFrom-Json
$legacy
$contract.name
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket $legacy
terraform state list
terraform destroy -auto-approve
Set-Location ..
Remove-Item .\work -Recurse -Force
Get-ChildItem -Force
```

旧输出、新输出、API 与 state 必须指向同一 bucket。销毁后查询失败；源目录恢复为
`Readme.md` 与 `challenge-43.tf`。

## LocalStack 提醒

- 向后兼容指保留调用者可见的变量/输出，不代表永远保留所有旧接口。
- Root moved block 与 child moved block 的地址作用域不同。
- LocalStack 不参与地址迁移；它只用于确认 AWS 对象没有被替换。
