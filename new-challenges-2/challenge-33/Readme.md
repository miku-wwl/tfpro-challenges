# Challenge 33：规范化 Optional、Null 与分层配置优先级

这个练习从一个使用固定属性的 S3 bucket 开始。输入对象已经允许 optional 字段，但资源
尚未消费它们。你会区分“省略”和显式值，建立全局默认、环境默认、调用者覆盖三层优先级，
再让 bucket 与输出只依赖一份规范化合同。

## 官方考试目标

- **2a**：Use language features to validate configuration
- **2c**：Compute and interpolate data using HCL functions
- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types
- **3c**：Use the Terraform workflow in automation

使用官方 AWS 学习资源中的 `aws_s3_bucket` 与 `aws_s3_object`。兼容
Terraform `>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-33
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 已包含：

- 类型为 object 的 `storage_request`，其中三个字段可以省略；
- 一个名为 `tfpro-c33-normalization` 的可销毁 S3 bucket；
- 固定 tags 与 `starter_storage` 输出；
- 尚无环境默认、规范化 local 或 manifest object。

## Task 1：部署固定基线并观察 Null

```powershell
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output starter_storage
terraform console
```

在 console 中依次查看：

```hcl
var.storage_request
var.storage_request.publish_manifest
var.storage_request.force_destroy
var.storage_request.tags
```

省略且没有 optional 默认值的字段应为 `null`；这不等于 `false` 或空 map。退出 console。

## Task 2：添加输入边界

为 `storage_request` 添加 validation：

- environment 只能是 `dev`、`stage`、`prod`；
- 若 tags 非 null，key 与 value 都不能为空字符串。

```powershell
terraform fmt
terraform validate
terraform plan '-var=storage_request={environment="qa"}'
```

预期 plan 被清晰的 validation message 拒绝。默认输入仍应：

```powershell
terraform plan
```

显示 `No changes`。

## Task 3：建立三层优先级

添加 locals，按以下顺序生成一份完整 `normalized_storage`：

1. 全局默认：不发布 manifest、force_destroy true、基础 tags；
2. 环境默认：`prod` 默认发布 manifest，其余环境默认不发布；
3. 调用者给出的非 null 字段覆盖前两层；
4. `Name`、`Challenge`、`Environment` 三个强制 tag 最后合并，不能被调用者覆盖。

不要用 `try` 隐藏真实类型错误；只处理已声明的 optional/null。添加临时输出后运行：

```powershell
terraform console
```

检查默认输入、显式 `publish_manifest = false` 和显式空 tags 的差异。退出后执行
`terraform plan`，资源尚未接线，所以仍应 `No changes`。

## Task 4：让资源只消费规范化合同

将 bucket 的 `force_destroy` 与 tags 改为读取 `local.normalized_storage`，再添加
`aws_s3_object.manifest`：用 conditional `count` 决定零或一个实例，固定 key 为
`release/manifest.json`，内容包含 environment。它也只能读取 normalized local，不要在多个
资源中重复优先级表达式。

```powershell
terraform plan '-out=normalized.tfplan'
terraform show normalized.tfplan
terraform apply normalized.tfplan
Remove-Item -LiteralPath .\normalized.tfplan
terraform plan
```

默认 dev 合同应保持零个 manifest object，最终 plan 为 `No changes`。

## Task 5：验证显式覆盖优先于环境默认

分别生成两个不应用的计划：

```powershell
terraform plan '-var=storage_request={environment="prod"}'
terraform plan '-var=storage_request={environment="prod",publish_manifest=false,tags={Owner="release"}}'
```

第一个计划应创建 manifest；第二个必须保持零 object，因为显式 `false` 高于 prod 默认。
两个计划的强制 tags 都必须存在。之后回到默认输入并发布 `storage_contract`，至少包含
bucket name/ARN、environment、最终 publish_manifest、nullable manifest key、force_destroy
与排序后的 tags。Nullable key 使用 `one(aws_s3_object.manifest[*].key)`，不要直接索引
`[0]`。

## Task 6：从 State 与 API 验收并清理

```powershell
terraform apply -auto-approve
terraform output storage_contract
terraform state show aws_s3_bucket.normalized
aws --endpoint-url=http://localhost:4566 s3api list-objects-v2 --bucket tfpro-c33-normalization
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c33-normalization
terraform plan
terraform destroy -auto-approve
```

默认 dev 的 state/output/API 都应表明没有 manifest，tags 应一致，最终 plan 为
`No changes`。销毁后
`head-bucket` 应失败。删除所有运行产物，目录只保留两个 starter 源文件。

## LocalStack 提醒

- `list-objects-v2` 的 Contents 为空表示 dev 默认没有发布 manifest，不是查询失败。
- 本题讨论的是 Terraform optional/null 语义，不依赖真实 S3 数据。
- bucket 名固定且全局共享；若上次练习未清理，请先删除同名 LocalStack bucket。
