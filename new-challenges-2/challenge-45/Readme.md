# Challenge 45：用类型化 Output→Input 合同组合两个 Modules

这个练习从一个单体 S3 bucket、IAM publisher role、managed policy 与 attachment 开始。你会把
storage 与 publisher 分别提取为 child module，并让 publisher 的类型化 input 直接消费
storage output。根模块只负责组合，不复制 bucket name/ARN，也不添加手工 depends_on。

## 官方考试目标

- **4a**：Create a module
- **4b**：Use a module in configuration
- **2e**：Configure input variables and outputs, including complex types

使用官方 AWS `aws_s3_bucket`、`aws_iam_role`、`aws_iam_policy` 与
`aws_iam_role_policy_attachment`。兼容
Terraform `>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-45
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 单体配置创建 `tfpro-c45-storage`、`tfpro-c45-publisher` role 与允许
`s3:PutObject` 的 managed policy/attachment。Policy 直接引用根 bucket ARN。所有 module 文件在临时
`work` 副本中创建。

## Task 1：部署单体组合基线

```powershell
New-Item -ItemType Directory .\work
Copy-Item .\challenge-45.tf .\work\main.tf
Set-Location .\work
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output starter_composition
terraform state list
```

state 应包含 bucket、IAM role、managed policy、attachment 四个根资源。

## Task 2：提取 Storage Module 与 Contract

创建 `modules/storage`：

- 输入 object 含 bucket name、release label、force_destroy；
- 资源名为 `aws_s3_bucket.this`；
- 输出 `contract`，至少含 contract version、name、ARN；
- 不在 module 内配置 AWS provider。

根模块添加 `module "storage"`，并用 moved block 把根 bucket 映射到 module 地址。IAM
policy 暂时改为引用 `module.storage.contract.arn`。

```powershell
New-Item -ItemType Directory .\modules\storage
New-Item -ItemType File .\modules\storage\main.tf
New-Item -ItemType File .\modules\storage\variables.tf
New-Item -ItemType File .\modules\storage\outputs.tf
terraform fmt -recursive
terraform init
terraform validate
terraform plan '-out=storage.tfplan'
terraform show storage.tfplan
```

预期 bucket 不重建，IAM policy JSON 语义不变，attachment 保持不变。确认后 apply。

## Task 3：提取 Publisher Module 并直接接线

创建 `modules/publisher`。其输入包括：

- `role_name` string；
- `storage` object，字段精确声明 contract version、bucket name、bucket ARN。

移动 IAM role、policy 与 attachment，三种资源的本地名称均为 `this`。Policy 的 Resource
从 `var.storage.bucket_arn` 计算，attachment 连接 module 内 role/policy。根 module call 必须直接写
`storage = module.storage.contract`，不能复制 name/ARN 到 local 常量。

添加三条 moved blocks 映射旧 IAM 地址。

```powershell
New-Item -ItemType Directory .\modules\publisher
New-Item -ItemType File .\modules\publisher\main.tf
New-Item -ItemType File .\modules\publisher\variables.tf
New-Item -ItemType File .\modules\publisher\outputs.tf
terraform fmt -recursive
terraform init
terraform validate
terraform plan '-out=publisher.tfplan'
terraform show publisher.tfplan
```

预期 role/policy/attachment 都不 destroy/create。确认后 apply，state 地址应全部位于两个 modules。

## Task 4：发布根级 Composition Contract

根输出 `composition_contract` 至少包含 storage contract、publisher role name/ARN、
policy ARN 和 publisher 看到的 bucket ARN。输出必须从两个 module outputs 组装。

```powershell
terraform apply publisher.tfplan
Remove-Item .\storage.tfplan -ErrorAction SilentlyContinue
Remove-Item .\publisher.tfplan
terraform output composition_contract
terraform graph |
  Select-String -Pattern 'module.storage|module.publisher'
```

依赖图应能从 publisher input 推导到 storage output；不要额外添加
`depends_on = [module.storage]`。

## Task 5：强化类型合同并做单向更新

在 publisher input validation 或 resource precondition 中要求 contract version 为 `1`，
bucket ARN 以 `arn:aws:s3:::` 开头。默认配置应：

```powershell
terraform validate
terraform plan
```

显示 `No changes`。随后只把 storage module input 的 release label 从 `v1` 改成 `v2`：

```powershell
terraform plan '-out=v2.tfplan'
terraform show v2.tfplan
terraform apply v2.tfplan
Remove-Item .\v2.tfplan
terraform plan
```

预期只更新 bucket tag/合同；bucket ARN 不变，所以 IAM policy/attachment 不应变化。最终
`No changes`。

## Task 6：从两个 AWS API 验收并清理

```powershell
$contract = terraform output -json composition_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket $contract.storage.name
aws --endpoint-url=http://localhost:4566 iam get-policy --policy-arn $contract.publisher.policy_arn
aws --endpoint-url=http://localhost:4566 iam list-attached-role-policies --role-name $contract.publisher.role_name
terraform state list
terraform plan
terraform destroy -auto-approve
Set-Location ..
Remove-Item .\work -Recurse -Force
Get-ChildItem -Force
```

IAM policy 的 Resource 应由 storage ARN 加 `/*` 得到，且 attachment 应连接同一 role/policy；
state 只能显示 module 地址。销毁后
两个 API 查询都应失败，源目录恢复为两个 starter 文件。

## LocalStack 提醒

- IAM policy version document 的 API 响应可能 URL encode；验收 ARN/Action 语义，不比较空白。
- Output→input 引用会建立依赖边，不需要手工 `depends_on`。
- module 临时文件只存在于 `work`；最终仓库不包含 modules、脚本或 fixtures。
