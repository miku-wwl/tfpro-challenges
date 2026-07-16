# Challenge 75：跨 Configuration 的 Remote State 合同

这一题包含三个独立 root。Producer 发布最小、非敏感的 root output；Consumer 起初复制了一份相同合同，随后必须改成通过 S3 `terraform_remote_state` 读取。迁移时真实资源应零变更，Producer 升级后 Consumer 必须显式接受新版本。

```text
bootstrap local state
        │ 创建 state Bucket
        ▼
producer remote state ── release_contract ──▶ consumer remote state
        │                                      │
        └─ release Bucket + manifest            └─ receipts Bucket + receipt
```

目录中只包含 md/tf：

```text
challenge-75/
├── Readme.md
├── bootstrap/bootstrap.tf
├── producer/producer.tf
└── consumer/consumer.tf
```

## State 与权限边界

- Bootstrap local state 只管理共享 state Bucket。
- Producer 使用 `challenge75/producer.tfstate`，只管理 release Bucket/object。
- Consumer 使用 `challenge75/consumer.tfstate`，只管理 receipts Bucket/object。
- Consumer 可以读取 Producer output，但绝不能管理 Producer 资源或直接读取 Producer 配置文件。

`terraform_remote_state` 表面上只暴露 root outputs，但读取者实际上需要读取完整 state snapshot 的权限。因此合同中禁止放 secret；真实平台应优先考虑权限更窄的显式发布存储。

## 开始前检查

请使用新开的专用 PowerShell 终端；关闭它即可回到原有凭证环境，不要在正在使用
真实 AWS credentials 的会话中覆盖变量。所有 AWS CLI 命令都必须保留显式
LocalStack endpoint。

```powershell
docker ps
aws --version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

## 任务

### Task 1：创建共享 State Bucket

```powershell
Set-Location .\new-challenges-3\challenge-75\bootstrap
terraform init
terraform validate
terraform apply -auto-approve
terraform output -raw state_bucket
```

输出必须是 `tfpro-challenge75-state`。该 Bucket 只能留在 bootstrap state。

### Task 2：部署 Producer 并发布 Root Output

```powershell
Set-Location ..\producer
terraform init `
  '-backend-config=bucket=tfpro-challenge75-state' `
  '-backend-config=key=challenge75/producer.tfstate'

terraform validate
terraform apply -auto-approve
terraform state list
terraform output -json release_contract
```

Producer state 应只有 release Bucket 和 manifest object。合同必须包含：

- `schema_version = 1`
- `release = "v1"`
- Bucket、object key
- payload 的 SHA-256

用 CLI 确认 Producer state object 存在：

```powershell
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-challenge75-state `
  --key challenge75/producer.tfstate
```

### Task 3：部署使用复制合同的 Legacy Consumer

切换到 consumer。Starter 中的 `local.legacy_contract` 是故意留下的协作缺陷，但它与 Producer v1 output 的值完全相同：

```powershell
Set-Location ..\consumer
terraform init `
  '-backend-config=bucket=tfpro-challenge75-state' `
  '-backend-config=key=challenge75/consumer.tfstate'

terraform validate
terraform apply -auto-approve
terraform state list
terraform output -json consumed_contract
```

Consumer state 应只有 receipts Bucket 和 receipt object，不能出现任何 Producer 资源地址。

### Task 4：改用 `terraform_remote_state`，保持零资源变更

编辑 `consumer/consumer.tf`：

1. 添加 `data "terraform_remote_state" "producer"`，backend 使用 `s3`。
2. 在 data source 的 `config` 中指定 state Bucket、`challenge75/producer.tfstate`、`us-east-1`、`endpoints.s3 = "http://localhost:4566"` 和 `use_path_style = true`；同时启用 `skip_credentials_validation`、`skip_metadata_api_check`、`skip_region_validation`、`skip_requesting_account_id` 与 `skip_s3_checksum`。凭证继续来自环境变量。
3. 删除整份 `local.legacy_contract`，让 `local.contract` 来自 `data.terraform_remote_state.producer.outputs.release_contract`。
4. 不修改 receipts Bucket/object 的地址、key 或合同编码方式。

`terraform_remote_state` 是 Terraform 内建 data source，不需要声明额外 Provider。完成后执行：

```powershell
terraform fmt
terraform validate
terraform plan
```

由于新旧合同值相同，plan 必须是 `No changes`。如果 receipt 要更新或替换，先比较两份合同，不要 apply 非零迁移计划。

### Task 5：观察合同升级与 Stale Consumer 拒绝

切换到 producer，把 `local.release` 从 `v1` 改成 `v2`，再部署：

```powershell
Set-Location ..\producer
terraform apply -auto-approve
terraform output -json release_contract
```

回到 consumer，先保持 `expected_release = "v1"`：

```powershell
Set-Location ..\consumer
terraform plan
```

这是本题的**预期失败**：precondition 必须报告 Producer release 与 Consumer expected release 不一致，防止未经确认自动消费 v2。

确认升级后，把 Consumer 的 `expected_release` default 改为 `v2`，然后执行：

```powershell
terraform plan
terraform apply -auto-approve
terraform output -json consumed_contract
terraform plan
```

计划只能原地更新 `aws_s3_object.receipt`；不能重建两个 Bucket。最终 output release 必须是 `v2`，最后一次 plan 必须为 `No changes`。

应用后 `terraform state list` 可能额外显示 `data.terraform_remote_state.producer`。这是 Consumer 读取 Producer output 的只读 data source，不是由 Consumer 管理的 Producer 资源；`aws_s3_bucket.release` 与 `aws_s3_object.manifest` 仍不能出现在 Consumer state 中。

## 清理

Consumer 依赖 Producer output，Producer 与 Consumer 又都依赖 bootstrap state Bucket。必须按 Consumer → Producer → Bootstrap 清理：

```powershell
# 当前目录：challenge-75/consumer
terraform destroy -auto-approve

Set-Location ..\producer
terraform destroy -auto-approve

Set-Location ..\bootstrap
terraform destroy -auto-approve
```

不要先删 Producer 或 state Bucket。最后删除三个 root 中运行时生成的 `.terraform/`、lock 和 state，只保留 md/tf。

## 考纲对应

- 3b：两个独立 root 使用不同 S3 state key。
- 3d：通过版本化 root output 在配置间共享数据。
- 2a：用 precondition 拒绝 stale contract。

官方入口：[`terraform_remote_state`](https://developer.hashicorp.com/terraform/language/state/remote-state-data)、[Remote state](https://developer.hashicorp.com/terraform/language/state/remote)、[Custom conditions](https://developer.hashicorp.com/terraform/language/expressions/custom-conditions)。
