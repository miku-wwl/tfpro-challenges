# Challenge 37：把 Local State 迁移到 Partial S3 Backend

这个练习先用本地 state 管理一个 S3 workload bucket，再由 AWS CLI 在 LocalStack 创建
独立的 state bucket。你会添加空的 S3 backend block，通过临时 backend config 迁移
已有 state，并证明凭证和 endpoint 配置没有被提交进 Terraform 源文件。

## 官方考试目标

- **1a**：Initialize a configuration using `terraform init` and its options
- **3b**：Configure remote state
- **5c**：Manage provider authentication

使用官方 AWS `aws_s3_bucket` 资源与 Terraform S3 backend。流程按 Terraform 1.6
兼容参数编写；starter 支持 `>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-37
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

`challenge-37.tf` 目前没有 backend block。`tfpro-c37-workload` 由默认 local backend
管理；`tfpro-c37-state` 尚不存在。

## Task 1：创建 Local State 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform state list
Get-Item -LiteralPath .\terraform.tfstate
terraform output starter_backend_contract
```

预期 local state 中只有 workload bucket，当前目录存在 `terraform.tfstate`。

## Task 2：用 AWS CLI 创建 Backend 基础设施

Backend bucket 不能由将要使用它的同一份 state 创建。使用 AWS CLI：

```powershell
aws --endpoint-url=http://localhost:4566 s3api create-bucket `
  --bucket tfpro-c37-state
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c37-state
```

预期 state bucket 存在；它不应出现在当前 Terraform state。

## Task 3：声明 Partial Backend 并迁移

在现有 `terraform` block 中加入空的 `backend "s3" {}`。不要在 TF 中写 bucket、key、
endpoint 或 credentials。创建一个临时且不提交的 `backend.hcl`：

```powershell
@'
bucket                      = "tfpro-c37-state"
key                         = "challenge-37/terraform.tfstate"
region                      = "us-east-1"
endpoint                    = "http://localhost:4566"
force_path_style            = true
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_region_validation      = true
skip_requesting_account_id  = true
'@ | Set-Content -LiteralPath .\backend.hcl -Encoding utf8

terraform init -migrate-state '-backend-config=backend.hcl'
```

确认迁移提示后输入 `yes`。预期 Terraform 把既有 workload state 复制到 S3，而不是重新
创建 bucket。`backend.hcl` 不含 access/secret key；backend 从环境变量读取 test 凭证。

## Task 4：证明远端对象是权威 State

```powershell
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c37-state `
  --key challenge-37/terraform.tfstate
terraform plan
```

state 仍列出 `aws_s3_bucket.workload`，S3 object 存在，plan 为 `No changes`。即使本地
留有迁移 backup，它也不是当前 backend 的权威 state。

## Task 5：通过远端 State 完成一次更新

把 workload 的 `Release` tag 从 `v1` 改为 `v2`：

```powershell
$before = (aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c37-state `
  --key challenge-37/terraform.tfstate | ConvertFrom-Json).ETag
terraform plan '-out=remote-update.tfplan'
terraform show remote-update.tfplan
terraform apply remote-update.tfplan
Remove-Item -LiteralPath .\remote-update.tfplan
terraform plan
$after = (aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c37-state `
  --key challenge-37/terraform.tfstate | ConvertFrom-Json).ETag
$before
$after
```

预期只有 tag 原地更新，远端 state object 的 ETag 发生变化，最终 plan 为 `No changes`。

## Task 6：从 State 与 API 验收并清理

先在 backend 仍可用时销毁 workload：

```powershell
terraform output starter_backend_contract
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c37-workload
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 s3 rm s3://tfpro-c37-state --recursive
aws --endpoint-url=http://localhost:4566 s3api delete-bucket `
  --bucket tfpro-c37-state
Remove-Item -LiteralPath .\backend.hcl
```

workload API 查询应在销毁后失败，Terraform state list 应为空。最后删除 `.terraform`、
lockfile、local state/backup 与 plan；目录只保留 README 和 TF。TF 中不能出现 backend
凭证。

## LocalStack 与 Terraform 1.6 提醒

- 本题使用 Terraform 1.6 可识别的 S3 backend `endpoint`/`force_path_style` 参数；
  新版本可能显示弃用提示，但不影响本题目标。
- LocalStack S3 backend 只用于本机练习，不等同于生产 durability。
- 永远先销毁受管 workload，再删除承载其 state 的 backend bucket。
