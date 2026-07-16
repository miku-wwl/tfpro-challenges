# Challenge 73：Terraform 1.6 S3 + DynamoDB 真实锁竞争

这一题使用 Terraform 1.6 的 S3 backend 与 DynamoDB locking，模拟两个协作者同时操作同一份 state。你会让 Terminal A 真正持锁，在 Terminal B 观察 `-lock-timeout` 失败，再通过正常结束持锁操作安全释放。

Terraform 1.6 尚不支持后来加入 S3 backend 的 `use_lockfile`。本题必须使用 `dynamodb_table`，且表的 partition key 必须是字符串 `LockID`。

```text
challenge-73/
├── Readme.md
├── bootstrap/
│   └── bootstrap.tf
└── app/
    └── app.tf
```

`bootstrap.tf` 只能创建 S3 state Bucket。DynamoDB 表必须使用下面给出的 AWS CLI 命令创建、检查和删除；不要添加 `aws_dynamodb_table`，也不要生成脚本。

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

### Task 1：创建 State Bucket 与 Lock Table

先创建由独立 local state 管理的 S3 Bucket：

```powershell
Set-Location .\new-challenges-3\challenge-73\bootstrap
terraform init
terraform validate
terraform apply -auto-approve
```

再用可复制的 AWS CLI 命令创建锁表：

```powershell
aws --endpoint-url=http://localhost:4566 dynamodb create-table `
  --table-name tfpro-challenge73-locks `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST

aws --endpoint-url=http://localhost:4566 dynamodb describe-table `
  --table-name tfpro-challenge73-locks
```

确认表为 `ACTIVE`，hash key 名称精确为 `LockID`、类型为 `S`。

### Task 2：初始化带锁的 Partial Backend

切换到 app。`app.tf` 已包含 LocalStack backend 的 endpoint 与 skip 参数，但故意省略 bucket、key 和 table：

```powershell
Set-Location ..\app
terraform init `
  '-backend-config=bucket=tfpro-challenge73-state' `
  '-backend-config=key=challenge73/app.tfstate' `
  '-backend-config=dynamodb_table=tfpro-challenge73-locks'

terraform validate
terraform apply -auto-approve -var='release=v1'
terraform state list
terraform plan -var='release=v1'
```

state 中应只有 `aws_s3_bucket.application`，最后一次 plan 应为 `No changes`。Bootstrap state、app remote state 与 DynamoDB 表是三个不同的所有权边界。

### Task 3：在 Terminal A 持有真实锁

打开两个 PowerShell 终端，并让两者都进入 `challenge-73/app`。新开的终端不会自动继承你在另一个 PowerShell 会话中临时设置的变量，因此请在 **A、B 两边**都确认 `AWS_ACCESS_KEY_ID=test`、`AWS_SECRET_ACCESS_KEY=test` 和 `AWS_DEFAULT_REGION=us-east-1`。

在 **Terminal A** 执行：

```powershell
terraform apply -var='release=v2' -lock-timeout=30s
```

命令生成变更计划后会停在 `Enter a value:`。此时先不要输入；Terraform 在等待确认期间仍持有同一 state lock。

### Task 4：在 Terminal B 观察锁超时

保持 A 停在确认提示，在 **Terminal B** 执行：

```powershell
terraform plan -var='release=v2' -lock-timeout=5s
```

这是本题的**预期失败**。等待约 5 秒后应出现 `Error acquiring the state lock`，并显示 lock ID、operation 和 holder 信息。检查真实 DynamoDB 记录：

```powershell
aws --endpoint-url=http://localhost:4566 dynamodb scan `
  --table-name tfpro-challenge73-locks
```

持锁记录会包含 `Info`。表中还可能有用于 S3 state 一致性检查的 `Digest` 记录，不要把 checksum 记录误认成活动锁。

不要使用 `-lock=false` 绕过竞争，也不要对仍在运行的 Terminal A 执行 `force-unlock`。

### Task 5：正常释放并完成变更

回到 Terminal A 输入 `no`。正常取消会释放锁。Terraform 1.6.6 会显示 `Apply cancelled`，该进程也可能返回退出码 `1`；这里应以 Terminal B 能否重新获得锁判断释放是否成功，不要把取消进程的退出码误认成锁残留。随后在 Terminal B 执行：

```powershell
terraform plan -var='release=v2' -lock-timeout=5s
terraform apply -auto-approve -var='release=v2'
terraform plan -var='release=v2'
terraform output application_release
```

第一次 plan 现在必须能获得锁；apply 后输出 release 为 `v2`；最终 plan 为 `No changes`。再次 scan DynamoDB 时，不应再有带 `Info` 的活动锁记录，但 `Digest` 记录可以保留。

## 清理

必须先让最后一次 app 操作完成并释放锁，然后按 app → lock table → bootstrap 的顺序清理：

```powershell
# 当前目录：challenge-73/app
terraform destroy -auto-approve -var='release=v2'

aws --endpoint-url=http://localhost:4566 dynamodb delete-table `
  --table-name tfpro-challenge73-locks

Set-Location ..\bootstrap
terraform destroy -auto-approve
```

不要在 app destroy 完成前删除 DynamoDB 表或 state Bucket。最后删除运行时生成的缓存、lock file 和 state。

## 考纲对应

- 3b：使用 S3 remote state 与 Terraform 1.6 DynamoDB locking。
- 3c：理解自动化/协作运行中的锁等待、失败与安全释放。

官方入口：[Terraform 1.6 S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)、[State locking](https://developer.hashicorp.com/terraform/language/state/locking)、[`terraform plan -lock-timeout`](https://developer.hashicorp.com/terraform/cli/commands/plan)。
