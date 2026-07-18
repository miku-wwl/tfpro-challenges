# Challenge 38：在两个终端观察 S3 + DynamoDB State Lock

这个练习使用 Terraform 1.6 的 S3 backend 与 DynamoDB locking。你会先创建本地基线，
再用 AWS CLI 准备 backend 基础设施；随后让终端 A 在 apply 确认阶段持有锁，终端 B
用短 timeout 证明并发操作会被拒绝。

## 官方考试目标

- **3b**：Configure remote state
- **3c**：Use the Terraform workflow in automation

使用 Terraform 1.6 的 S3 backend/DynamoDB lock 行为以及核心 `terraform_data`。兼容
Terraform `>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-38
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 只有 local backend、`lease_generation = 1` 和 `terraform_data.lease`。S3 bucket
`tfpro-c38-state` 与 DynamoDB table `tfpro-c38-locks` 尚不存在。

## Task 1：创建本地 Lease 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output starter_lease
terraform state show terraform_data.lease
```

generation 应为 `1`，当前 state 位于本地。

## Task 2：用 CLI 创建 Backend 与 Lock Table

```powershell
aws --endpoint-url=http://localhost:4566 s3api create-bucket `
  --bucket tfpro-c38-state

aws --endpoint-url=http://localhost:4566 dynamodb create-table `
  --table-name tfpro-c38-locks `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST

aws --endpoint-url=http://localhost:4566 dynamodb describe-table `
  --table-name tfpro-c38-locks `
  --query 'Table.{Name:TableName,Status:TableStatus,Key:KeySchema}'
```

预期 table 为 ACTIVE，partition key 精确为字符串 `LockID`。两项 backend 基础设施均不
属于当前 Terraform state。

## Task 3：迁移到带 DynamoDB Lock 的 S3 Backend

在 `terraform` block 添加空的 `backend "s3" {}`，再创建临时 `backend.hcl`：

```powershell
@'
bucket                      = "tfpro-c38-state"
key                         = "challenge-38/terraform.tfstate"
region                      = "us-east-1"
endpoint                    = "http://localhost:4566"
force_path_style            = true
dynamodb_table              = "tfpro-c38-locks"
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_region_validation      = true
skip_requesting_account_id  = true
'@ | Set-Content -LiteralPath .\backend.hcl -Encoding utf8

terraform init -migrate-state '-backend-config=backend.hcl'
terraform state list
```

输入 `yes` 完成迁移。state 地址与 generation 必须保持不变。

## Task 4：让终端 A 持有 State Lock

把 `lease_generation` 默认值改为 `2`。打开两个 PowerShell 窗口，都进入本题目录并设置
相同 AWS 环境变量。

终端 A 运行：

```powershell
terraform apply
```

当它显示计划并等待 `Enter a value:` 时先不要输入；此时 apply 已持有 state lock。

终端 B 运行：

```powershell
terraform plan '-lock-timeout=5s'
$LASTEXITCODE
```

约 5 秒后必须以非零退出码失败，并报告 `Error acquiring the state lock`。不能使用
`-lock=false` 绕过保护。

## Task 5：观察 Lock Row 的创建与释放

保持终端 A 等待，在终端 B 查询：

```powershell
aws --endpoint-url=http://localhost:4566 dynamodb scan `
  --table-name tfpro-c38-locks
```

应看到一条包含 LockID/Info 的临时 row。回到终端 A 输入 `yes`；apply 完成后再在
终端 B 运行同一 scan，预期 Items 为空。最后：

```powershell
terraform plan
terraform output starter_lease
```

generation 应为 `2`，plan 为 `No changes`。

## Task 6：验收远端 State 并按顺序清理

```powershell
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c38-state `
  --key challenge-38/terraform.tfstate
terraform state list
terraform destroy -auto-approve

aws --endpoint-url=http://localhost:4566 s3api delete-object `
  --bucket tfpro-c38-state `
  --key challenge-38/terraform.tfstate
aws --endpoint-url=http://localhost:4566 s3api delete-bucket `
  --bucket tfpro-c38-state
aws --endpoint-url=http://localhost:4566 dynamodb delete-table `
  --table-name tfpro-c38-locks
Remove-Item -LiteralPath .\backend.hcl
```

销毁前远端 state object 必须存在；销毁后 state list 为空，lock table 也不应残留 row。
删除运行产物，最终只留两个源文件。

## LocalStack 与 Terraform 1.6 提醒

- 本题刻意使用 Terraform 1.6 的 DynamoDB locking；较新 Terraform 的 S3 lockfile
  方案不在本题范围。
- 等待交互确认是一种可重复的本地持锁方法，不代表生产 apply 应长时间暂停。
- DynamoDB table 必须使用精确的 `LockID` 字符串 partition key。
