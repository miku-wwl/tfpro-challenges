# Challenge 20：用 Import Block 接管 CLI 创建的 S3 Bucket

一个遗留 bucket 已在平台中存在，却还没有 Terraform owner。本题先用 AWS CLI 在
LocalStack 创建并打标签，再补齐 resource 与 Terraform 1.6 import block。合格的接管计划
只能 import，不能新建、修改或销毁远端对象。

## 官方考试目标

- **1b**：生成并审阅 declarative import plan
- **1c**：应用同一份 import plan
- **1e**：导入既有资源并安全管理 state

本题只使用官方学习范围中的 `aws_s3_bucket`。Terraform 范围为
`>= 1.6.0, < 2.0.0`，AWS provider 固定为 `5.80.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-20
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
Invoke-RestMethod http://localhost:4566/_localstack/health
```

Starter 只有 provider、`local.bucket_name`、`local.bucket_tags` 和一个只读 output，没有
resource 或 import block，也没有 state。目标物理名称固定为 `tfpro-c20-imported`。

## Task 1：验证尚未声明资源的 Starter

```powershell
terraform init -input=false
terraform fmt -check
terraform validate
'local.bucket_name' | terraform console
'local.bucket_tags' | terraform console
terraform plan -input=false
terraform apply -auto-approve
terraform output -json starter_import_target
terraform state list
```

Console 应显示 `tfpro-c20-imported` 与三枚预期 tags。Plan 没有 managed resource 动作；
它最多显示尚未写入 state 的 root output 变化。Apply 只把 output 写入空 state，state list
没有资源地址；此时 Terraform 仍不管理任何 S3 对象。

## Task 2：用 AWS CLI 模拟遗留平台创建对象

```powershell
$bucketName = 'tfpro-c20-imported'
aws --endpoint-url=http://localhost:4566 s3api create-bucket `
  --bucket $bucketName
aws --endpoint-url=http://localhost:4566 s3api put-bucket-tagging `
  --bucket $bucketName `
  --tagging 'TagSet=[{Key=Name,Value=tfpro-c20-imported},{Key=Challenge,Value=20},{Key=Owner,Value=TerraformImport}]'
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket $bucketName
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket $bucketName
terraform state list
```

两个 API 查询成功且 tags 与 starter local 一致；Terraform state 仍为空。不要为了导入而
先用 Terraform create，也不要让第二个 state 同时拥有该 bucket。

## Task 3：补齐声明式 Resource 与 Import 合同

编辑 `challenge-20.tf`，完成两部分：

1. 添加地址为 `aws_s3_bucket.imported` 的 resource，bucket 名、tags 分别引用已有两个
   locals；不要设置 `force_destroy`，保持与新导入对象的 provider 默认值一致；
2. 添加一个 import block，`to` 指向该资源地址，`id` 引用 `local.bucket_name`。

不要复制 API 返回的 ARN、region 或 computed 属性到 resource。然后：

```powershell
terraform fmt
terraform validate
terraform plan -input=false -detailed-exitcode '-out=import.tfplan'
$LASTEXITCODE
terraform show import.tfplan
```

退出码应为 `2`，计划摘要必须是 **1 to import, 0 to add, 0 to change, 0 to destroy**。
如果出现 update，先对齐 CLI 预置 tags 与 HCL；如果出现 create，检查 import 的 `to` 和
resource 地址是否完全一致。计划未满足合同前不能 apply。

## Task 4：应用 Import，并证明物理身份未变

```powershell
terraform apply -input=false import.tfplan
terraform state list
terraform state show aws_s3_bucket.imported
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket $bucketName
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket $bucketName
```

State 现在只能有 `aws_s3_bucket.imported`，其 ID 必须仍是
`tfpro-c20-imported`。Import 建立 state 绑定，不会复制或重建 bucket。

## Task 5：移除一次性 Import 声明并检查幂等

从配置中只删除 import block，保留刚完成的 resource。然后运行：

```powershell
terraform fmt
terraform validate
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
terraform state show aws_s3_bucket.imported
```

退出码必须为 `0`。Import block 可以在已导入后保留而不重复执行；本题删除它，是为了把
一次性迁移意图与长期 resource 合同明确分开。

## Task 6：由新 Owner 销毁并恢复 Starter

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket $bucketName
$LASTEXITCODE
```

必须由已经接管对象的当前 state 执行 destroy。State 应为空，API 检查应非零。然后恢复
没有 resource/import 的 starter，并删除运行产物：

```powershell
git restore --source=HEAD -- .\challenge-20.tf
Remove-Item -LiteralPath .\.terraform -Recurse -Force
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,`
  .\terraform.tfstate.backup,.\import.tfplan `
  -Force -ErrorAction SilentlyContinue
git diff --exit-code -- .\challenge-20.tf
Get-ChildItem -Force | Select-Object -ExpandProperty Name
```

最终只保留 `Readme.md` 和 `challenge-20.tf`。

## Terraform 1.6 与 LocalStack 边界

- Terraform 1.6 支持 import block，但本题不使用 Terraform 1.7 才加入的 import
  `for_each`。
- Import ID 必须是 plan-time 已知值；这里使用固定 local，不依赖待导入资源的属性。
- Import 之前先确认对象存在、配置匹配且没有其他 state owner；它不是发现并批量接管资源的
  魔法命令。
- LocalStack 的测试 credentials 与 endpoint 只适合本机练习，不能替代真实 AWS 权限控制。
