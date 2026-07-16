# Challenge 94：Partial S3 Backend 的凭证持久化审计

AWS provider 与 S3 backend 是两套独立的认证边界。把 backend credentials 放进
`-backend-config` 虽然能成功初始化，但 Terraform 会把这些值写入本地 `.terraform`
backend metadata。本题只使用 LocalStack 的公开测试值 `test/test` 演示风险，再用环境变量
和 `terraform init -reconfigure` 清除持久化凭证。

> 安全边界：不要在本题中使用真实 AWS access key、secret key 或 profile。

## 考纲定位

- **2f**：Analyze best practices for managing sensitive data
- **3b**：Configure remote state
- **5c**：Manage provider authentication
- 辅助使用 **1a**：使用 `terraform init -reconfigure`

## State 边界与目录

```text
challenge-94/
├── Readme.md
├── bootstrap/
│   └── bootstrap.tf
└── workload/
    └── workload.tf
```

- `bootstrap` 使用 local state，只管理 `tfpro-c94-state`。
- `workload` 使用 partial S3 backend，管理 `tfpro-c94-release`。
- Backend bucket 绝不能加入 workload state。
- Provider 中的 `test/test` 不会自动传给 backend。

## 开始前

```powershell
Set-Location .\new-challenges-4\challenge-94
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
```

使用专用 PowerShell 终端。开始时不要依赖已有 AWS 环境变量：

```powershell
Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:AWS_DEFAULT_REGION -ErrorAction SilentlyContinue
```

## Task 1：创建独立 Backend Bucket

```powershell
Set-Location .\bootstrap
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output -raw state_bucket
terraform state list
```

输出必须是 `tfpro-c94-state`；bootstrap state 只能包含 `aws_s3_bucket.state`。

## Task 2：用 CLI Backend Config 完成一次不安全初始化

切换到 workload。Starter 的 backend block 已包含固定的 LocalStack endpoint 与安全 skip
flags，但故意省略 `bucket`、`key` 和 credentials。

```powershell
Set-Location ..\workload
terraform init `
  '-backend-config=bucket=tfpro-c94-state' `
  '-backend-config=key=challenge94/workload.tfstate' `
  '-backend-config=access_key=test' `
  '-backend-config=secret_key=test'
terraform validate
terraform apply -auto-approve
terraform state list
terraform output workload_contract
```

这一步只因 `test/test` 是 LocalStack 的公开假凭证而允许执行。真实秘密绝不能用这种方式
传给 `-backend-config`。

## Task 3：找到凭证究竟被写到了哪里

仍在 `workload`：

```powershell
$metadata = Get-Content .\.terraform\terraform.tfstate -Raw | ConvertFrom-Json
$metadata.backend.type
$metadata.backend.config.access_key
$metadata.backend.config.secret_key
```

预期依次看到 `s3`、`test`、`test`。`.terraform/terraform.tfstate` 是本机 backend metadata，
不是远端权威 resource state。

再检查源码与远端 state：

```powershell
Select-String -Path .\workload.tf -Pattern 'access_key\s*=|secret_key\s*='
terraform state pull | Select-String '"access_key"|"secret_key"'
```

第一条只会找到 AWS **provider** 的 LocalStack 测试值；第二条不应找到 backend credentials。
风险位置是本地 `.terraform` metadata，而不是 S3 中的 resource state JSON。

## Task 4：改用环境认证并清除 Backend Metadata 中的凭证

在这个专用终端设置 LocalStack-only 环境变量：

```powershell
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

不要再把 credentials 传给 init。用相同 bucket/key 重新配置：

```powershell
terraform init -reconfigure `
  '-backend-config=bucket=tfpro-c94-state' `
  '-backend-config=key=challenge94/workload.tfstate'
```

重新读取 metadata：

```powershell
$metadata = Get-Content .\.terraform\terraform.tfstate -Raw | ConvertFrom-Json
$null -eq $metadata.backend.config.access_key
$null -eq $metadata.backend.config.secret_key
```

两行必须都是 `True`。S3 backend metadata 保留固定 schema 字段，所以属性名仍可见；关键
证据是两个字段值已经从 `test` 变为 `null`。环境认证能被 backend process 使用，但凭证值
不会被序列化进 backend configuration metadata。

## Task 5：核验 Remote State 与资源均未被扰动

```powershell
terraform state list
terraform output workload_contract
terraform plan -detailed-exitcode
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c94-state `
  --key challenge94/workload.tfstate
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c94-release
```

最终 plan 退出码应为 `0`。`-reconfigure` 只刷新 backend 客户端配置，不得重建 workload
resource，也不得改变 state key。

## 清理

必须先销毁 workload，再销毁承载其 state 的 bootstrap bucket：

```powershell
# 当前目录：challenge-94/workload
terraform destroy -auto-approve

Set-Location ..\bootstrap
terraform destroy -auto-approve

Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:AWS_DEFAULT_REGION -ErrorAction SilentlyContinue
```

`tfpro-c94-state` 使用 `force_destroy`，会清除销毁后的 state object。不要提交 `.terraform`、
state 或 lockfile。

## Terraform 1.6 边界

本题使用 Terraform 1.6 S3 backend 的 partial configuration 与 `-reconfigure`。不要创建
backend 配置文件，不要把 backend block 改成变量插值，也不要使用真实云凭证、HCP
dynamic credentials、ephemeral values 或 write-only arguments。
