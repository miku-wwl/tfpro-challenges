# Challenge 72：Local State 到 Partial S3 Backend 的安全迁移

这一题练习在不重建真实资源的前提下，把已有 local state 迁移到 LocalStack S3 backend。你必须区分 bootstrap 与 workload 的 state，使用 partial backend 和 `terraform init -migrate-state`，并验证迁移前后的资源 ID 不变。

目录中只有 Terraform 与说明文件：

```text
challenge-72/
├── Readme.md
├── bootstrap/
│   └── bootstrap.tf
└── workload/
    └── workload.tf
```

## State 边界

- `bootstrap` 使用自己的 local state，只管理 `tfpro-challenge72-state`。
- `workload` 起初使用另一份 local state，只管理 `tfpro-challenge72-workload`。
- 迁移后，workload state 存在 bootstrap 创建的 Bucket 中；state Bucket 本身绝不能加入 workload state。

## 开始前检查

确认 LocalStack 可访问，并为 **S3 backend** 设置环境凭证。Backend 与 AWS Provider 是两套独立配置，Provider 中的 `test/test` 不会自动传给 backend。

请使用新开的专用 PowerShell 终端；关闭它即可回到原有凭证环境，不要在正在使用
真实 AWS credentials 的会话中覆盖变量。

```powershell
docker ps
aws --version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

## 任务

### Task 1：创建独立的 Backend 基础设施

从仓库根目录进入 bootstrap：

```powershell
Set-Location .\new-challenges-3\challenge-72\bootstrap
terraform init
terraform validate
terraform apply -auto-approve
terraform output -raw state_bucket
```

输出必须是 `tfpro-challenge72-state`。不要在 workload 中重复创建它。

### Task 2：先用 Local State 部署 Workload

切换到 workload，当前文件还没有 backend block，因此 Terraform 使用默认 local backend：

```powershell
Set-Location ..\workload
terraform init
terraform validate
terraform apply -auto-approve
terraform state list
terraform output -raw workload_bucket
```

state 中应只有 `aws_s3_bucket.workload`，输出应为 `tfpro-challenge72-workload`。迁移属于危险 state 操作，先把原始 state 备份到 challenge 目录之外：

```powershell
terraform state pull | Set-Content -Encoding utf8 "$env:TEMP\challenge72-local-state-backup.json"
```

### Task 3：添加不含秘密的 Partial S3 Backend

编辑 `workload/workload.tf`，在现有 `terraform` block 中添加 `backend "s3"`。HCL 中只配置这些固定、非敏感值：

- Region：`us-east-1`
- `endpoints.s3`：`http://localhost:4566`
- `use_path_style = true`
- `skip_credentials_validation = true`
- `skip_metadata_api_check = true`
- `skip_region_validation = true`
- `skip_requesting_account_id = true`
- `skip_s3_checksum = true`

**不要**在 HCL 中写 `bucket`、`key`、access key 或 secret key，也不要创建 backend 配置文件。Backend block 不能引用 input variable 或 local value。

添加后先执行一次：

```powershell
terraform plan
```

它应出现 `Backend initialization required` 一类错误。这是本题的预期教学点：backend 配置改变后，必须重新 init，不能继续 plan/apply。

### Task 4：迁移现有 State Lineage

仍在 workload 目录执行：

```powershell
terraform init -migrate-state `
  '-backend-config=bucket=tfpro-challenge72-state' `
  '-backend-config=key=challenge72/workload.tfstate'
```

Terraform 询问是否复制已有 state 时确认迁移。这里必须使用 `-migrate-state`；`-reconfigure` 会接受新 backend 配置，但不会表达“复制现有 state”的意图，不适合本步骤。

### Task 5：证明只迁移 State、没有重建资源

```powershell
terraform state list
terraform output -raw workload_bucket
terraform plan
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-challenge72-state `
  --key challenge72/workload.tfstate
```

验收条件：

- state 地址仍是 `aws_s3_bucket.workload`。
- Bucket ID 仍是 `tfpro-challenge72-workload`。
- S3 state object 存在。
- plan 为 `No changes`，不能出现 create、delete 或 replace。

## 清理

不要先销毁 bootstrap，否则 workload 会失去自己的权威 state。先在 `workload.tf` 中移除刚添加的 backend block，然后执行：

```powershell
# 当前目录：challenge-72/workload
terraform init -migrate-state
terraform state list
terraform destroy -auto-approve

Set-Location ..\bootstrap
terraform destroy -auto-approve
Remove-Item -LiteralPath "$env:TEMP\challenge72-local-state-backup.json" -Force -ErrorAction SilentlyContinue
```

最后删除两个目录中运行时生成的 `.terraform/`、`.terraform.lock.hcl` 和 state；不要删除 md/tf。

## 考纲对应

- 1a / 1e：重新初始化 backend、保护并迁移现有 state。
- 3b：配置 remote state，并理解 backend 凭证与 Provider 凭证的边界。

官方入口：[Backend configuration](https://developer.hashicorp.com/terraform/language/backend)、[S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)、[`terraform init`](https://developer.hashicorp.com/terraform/cli/commands/init)。
