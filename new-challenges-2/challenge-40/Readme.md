# Challenge 40：用 S3 Terraform Remote State 连接 Producer 与 Consumer

这个练习从一个单目录 release 配置开始，但不会在源目录 apply。你会临时创建
`producer` 与 `consumer` 两个工作目录，让 producer 把稳定合同写入 LocalStack S3
backend，consumer 再通过 `terraform_remote_state` 读取根输出，而不是复制 bucket 名。

## 官方考试目标

- **3b**：Configure remote state
- **3d**：Share data across configurations and workspaces

使用官方 AWS `aws_s3_bucket`、Terraform S3 backend、`terraform_remote_state` data
source 与核心 `terraform_data`。兼容 Terraform `>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-40
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

源目录只有 `Readme.md` 和 `challenge-40.tf`。TF 可以创建 `tfpro-c40-release` 并输出
versioned contract，但当前没有 backend block，也没有 producer/consumer 子目录。

## Task 1：只审阅 Source Preview

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=source-preview.tfplan'
terraform show source-preview.tfplan
Remove-Item -LiteralPath .\source-preview.tfplan
```

预期计划创建一个 release bucket。不要在源目录 apply；这里没有 state，TF 仍是可复制的
producer starter。

## Task 2：创建 Backend 与两个临时工作目录

```powershell
aws --endpoint-url=http://localhost:4566 s3api create-bucket `
  --bucket tfpro-c40-state

New-Item -ItemType Directory -Path .\producer, .\consumer
Copy-Item -LiteralPath .\challenge-40.tf -Destination .\producer\main.tf
```

预期 backend bucket 存在，两个临时目录为空或只含复制的 producer TF。它们是练习产物，
不能留在最终仓库。

## Task 3：部署 Producer Remote State

在 `producer/main.tf` 的 `terraform` block 加空 `backend "s3" {}`。在 producer 目录
创建临时 `backend.hcl`，使用：

- bucket `tfpro-c40-state`；
- key `challenge-40/producer.tfstate`；
- Region `us-east-1`；
- LocalStack endpoint、path style 与必要 skip flags；
- 不写 access/secret key，继续从环境变量读取。

```powershell
Set-Location .\producer
terraform init '-backend-config=backend.hcl'
terraform validate
terraform apply -auto-approve
terraform output release_contract
terraform state list
Set-Location ..
```

预期 producer 创建 `tfpro-c40-release`，远端 state 只含该 bucket。

## Task 4：编写并运行 Consumer

在 `consumer/main.tf` 编写一个独立 root module：

1. 声明相同 Terraform core 范围；
2. 添加 `data "terraform_remote_state" "producer"`，backend 为 `s3`；
3. config 指向 Task 3 的 bucket/key、LocalStack endpoint 与 1.6 path-style 参数；
4. 用 `terraform_data.snapshot` 保存 producer 的 `release_contract`；
5. 加 precondition，要求 `contract_version == 1`；
6. 输出 `consumed_release_contract`。

不要在 consumer 写死 release bucket 名或 ARN。

```powershell
Set-Location .\consumer
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output consumed_release_contract
terraform state list
Set-Location ..
```

consumer 输出必须与 producer 根输出一致，state 只管理 snapshot，不管理 producer bucket。

## Task 5：发布 V2 并观察 Consumer 刷新

把 `producer/main.tf` 中 `release_label` 默认值从 `v1` 改为 `v2`：

```powershell
Set-Location .\producer
terraform apply -auto-approve
terraform output release_contract
Set-Location ..\consumer
terraform plan '-out=consumer-refresh.tfplan'
terraform show consumer-refresh.tfplan
terraform apply consumer-refresh.tfplan
Remove-Item -LiteralPath .\consumer-refresh.tfplan
terraform plan
Set-Location ..
```

consumer 应只更新 snapshot/输出，不能创建或接管 S3 bucket；最终 plan 为 `No changes`。

## Task 6：双目录验收并按依赖顺序清理

```powershell
Set-Location .\consumer
terraform output consumed_release_contract
terraform destroy -auto-approve
Set-Location ..\producer
terraform output release_contract
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c40-release
terraform destroy -auto-approve
Set-Location ..

aws --endpoint-url=http://localhost:4566 s3api delete-object `
  --bucket tfpro-c40-state `
  --key challenge-40/producer.tfstate
aws --endpoint-url=http://localhost:4566 s3api delete-bucket `
  --bucket tfpro-c40-state
Remove-Item -LiteralPath .\producer -Recurse -Force
Remove-Item -LiteralPath .\consumer -Recurse -Force
```

先清 consumer，再销毁 producer，最后删除 backend。release API 查询在 producer destroy
后应失败。清除源目录 `.terraform`、lockfile 和任何 plan，最终只剩两个 starter 文件。

## LocalStack 与 Terraform 1.6 提醒

- Remote state 只公开 producer 的 root outputs，不允许 consumer 直接遍历 producer 资源。
- `terraform_remote_state` 会让有权读 state 的主体看到其中全部根输出；不要输出 secret。
- 临时目录使用 1.6 S3 endpoint/path-style 参数；新版本的弃用提示不改变本题合同。
