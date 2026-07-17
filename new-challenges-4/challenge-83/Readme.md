# Challenge 83：Plan-Time 已知的 `for_each` Key

Terraform 必须在 plan 阶段知道每个 resource instance 的地址。这个练习会让你亲眼看到
两类常见错误：把 apply 后才知道的随机结果当 key，以及把 sensitive value 当 key。
最终设计使用公开、稳定的业务名称作为地址；random 与 secret 仍可安全地出现在资源
value 中。

## 官方考试目标

- **2c**：Compute and interpolate data using HCL functions
- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types
- **2f**：Analyze best practices for managing sensitive data
- 辅助使用 **1b / 1c**：从失败计划迭代到可应用计划

使用官方学习资源中的 `random_integer`、`aws_s3_bucket` 和 `aws_s3_object`。本题严格兼容
Terraform `~> 1.6.0`；不要用较新 Terraform 的 mock 或 ephemeral 功能绕过问题。

## Starter 状态

```powershell
Set-Location .\new-challenges-4\challenge-83
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 包含：

- public `service_names = ["api", "worker"]`；
- sensitive `service_tokens`，其中只有明显的 LocalStack 假值；
- 一个可清空并销毁的 inventory bucket；
- 尚无 random resource 或 object resource。

这里的假 token 只是为了让 starter 可独立运行。真实 secret 不应写入配置或版本控制。

## Task 1：部署稳定的共享容器

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply baseline.tfplan
terraform output starter_bucket
Remove-Item -LiteralPath .\baseline.tfplan
```

预期只创建 1 个 S3 bucket。

## Task 2：先用公开业务名创建 Random Instances

添加 `random_integer.shard`：

- `for_each = var.service_names`；
- `min = 100`，`max = 999`；
- `keepers` 中记录 `each.key`。

只生成计划，**暂时不要 apply**：

```powershell
terraform fmt
terraform validate
terraform plan
```

预期成功，计划地址为：

```text
random_integer.shard["api"]
random_integer.shard["worker"]
```

业务名在 plan 前已知，而 `result` 仍显示 `(known after apply)`。

## Task 3：复现“Random Result 不能当 Key”

临时添加 `aws_s3_object.invalid_random_key`，让它的 `for_each` 使用两个
`random_integer.shard[*].result` 组成的 set。bucket 可引用 starter bucket，object key 可用
`each.key`。

```powershell
terraform plan
```

预期失败，核心信息是 `Invalid for_each argument`：Terraform 在 plan 阶段不能知道随机
结果，因此无法确定资源地址。不要使用 `-target` 分两次 apply 来掩盖错误；删除这个临时
resource block 后继续。

再次运行 `terraform plan`，必须恢复成功。

## Task 4：复现“Sensitive Value 不能当 Key”

再临时添加 `aws_s3_object.invalid_sensitive_key`，令 `for_each` 直接来自
`toset(values(var.service_tokens))`。

```powershell
terraform plan
```

预期在调用 AWS API 之前失败。Terraform 不允许 sensitive value 出现在 instance address，
因为地址会显示在 plan、state 与日志中。不要用 `nonsensitive(...)` 强行降级 token；删除
临时 block。

## Task 5：用已知业务 Key 承载未知与敏感 Value

添加正确的 `aws_s3_object.manifest`：

1. `for_each` 从 `service_names` 构造 `service => service` 的 map；
2. 使用 Task 1 创建的 bucket：`bucket = aws_s3_bucket.inventory.id`；
3. S3 object 的 `key` 使用 `"manifests/${each.key}.json"`，不要使用 random result、
   原始 token 或 token hash；
4. `content` 使用 `jsonencode`，包含当前 service、对应的 random result，以及对应
   token 的 SHA-256 摘要；
5. random result、原始 service token 和 token 的 SHA-256 摘要都只能放在 content
   中作为 value，不能用于 `for_each` key、resource name 或 S3 object key。

> **Note（☆）**：这里的“摘要”英文是 `digest`，指 token 经过 SHA-256
> 计算得到的固定长度、不可逆的 hash 指纹，不是文章的 `summary`。

```powershell
terraform plan '-out=manifests.tfplan'
terraform show manifests.tfplan
terraform apply manifests.tfplan
Remove-Item -LiteralPath .\manifests.tfplan
```

预期创建 2 个 random instances 与 2 个 S3 objects。plan 中 object content 应保持敏感，
但资源地址必须仍是 `manifest["api"]` 和 `manifest["worker"]`。

## Task 6：验证地址稳定、远端内容与清理

添加输出：

- `manifest_keys`：按业务名排序的 object keys，非敏感；
- `shard_contract`：service 到 shard result 的 map；
- 若输出包含 token 派生值，显式标记 `sensitive = true`。

```powershell
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform state list
terraform output manifest_keys

aws --endpoint-url=http://localhost:4566 s3api list-objects-v2 `
  --bucket tfpro-c83-plan-time-keys `
  --query 'Contents[].Key'

terraform plan
terraform destroy -auto-approve
```

把 `service_names` 的源码顺序反转后再 plan，也必须是 `No changes`；set 顺序不能改变
地址。销毁后清理 `.terraform`、lockfile、state 和 plan 文件，只留下 README 与 `.tf`。

## LocalStack 与敏感值边界

- `sensitive = true` 只遮蔽 CLI 展示；object content 仍会进入 Terraform state，也会被写到
  LocalStack S3。这里仅使用假 token。
- random provider 在本地运行，不经过 LocalStack；其 result 首次 plan 时未知。
- 不要把 token、token hash 或 random result 拼入 `for_each` key、resource name 或 S3 key。
