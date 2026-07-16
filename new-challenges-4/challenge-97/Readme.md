# Challenge 97：Remote-State Defaults 与向后兼容输出合同

Producer 增加一个 root output 时，Consumer 不一定能与它同一时刻发布。本题让两个配置
使用各自的 S3 remote state：Consumer 先用 `terraform_remote_state.defaults` 安全度过
旧 Producer 没有新 output 的阶段，再自动切换到 Producer 发布的真实值，最后用
precondition 拒绝不兼容的 schema major。

## 考纲定位

- **2a**：Use language features to validate configuration
- **2e**：Configure outputs, including complex types
- **3b**：Configure remote state
- **3d**：Share data across configurations and workspaces

范围依据：[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。

## State 与权限边界

本题有三份互相独立的配置：

| 配置 | State | 职责 |
| :--- | :--- | :--- |
| `bootstrap` | local | 只创建 `tfpro-c97-state` |
| `producer` | S3 key `challenge97/producer.tfstate` | 创建 artifacts bucket 并发布 outputs |
| `consumer` | S3 key `challenge97/consumer.tfstate` | 读取 Producer root outputs 并写 manifest |

所有 AWS API 都指向 LocalStack。`test/test` 只是 LocalStack 测试凭证；不要把真实云凭证写入
backend block、data source config 或版本库。

在 challenge 根目录设置本次 shell 的测试凭证：

```powershell
Set-Location .\new-challenges-4\challenge-97
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

## 任务

### Task 1：创建独立的 Backend 基础设施

```powershell
Set-Location .\bootstrap
terraform init
terraform apply -auto-approve
terraform output -raw state_bucket
```

输出必须是 `tfpro-c97-state`。不要把 bootstrap 自己迁入它创建的 backend。

### Task 2：发布没有可选策略输出的 Producer v1

```powershell
Set-Location ..\producer
terraform init '-backend-config=bucket=tfpro-c97-state'
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output release_contract
terraform output retention_policy
```

前三个部署命令应成功；最后一个 output 命令应按预期失败，因为 starter Producer 还没有
`retention_policy` root output。不要把“缺少可选的新 output”误判为 backend 读取失败。

### Task 3：让旧 Producer 下的 Consumer 使用明确默认值

```powershell
Set-Location ..\consumer
terraform init '-backend-config=bucket=tfpro-c97-state'
terraform validate
terraform plan '-out=consumer-v1.tfplan'
terraform apply consumer-v1.tfplan
terraform output consumed_policy
```

预期输出是 `schema_version = 1`、`days = 7`、`source = consumer-default`。核对真实对象：

```powershell
aws --endpoint-url=http://localhost:4566 s3 cp `
  s3://tfpro-c97-artifacts/releases/consumer-retention.json -
```

这里的 `defaults` 只为**缺失的 root output** 提供值；它不会递归补齐一个已存在对象中
缺少的属性。

### Task 4：发布真实 output 并观察 Consumer 自动切换

回到 `producer/producer.tf`，新增 root output `retention_policy`，合同必须是：

- `schema_version = 1`
- `days = 30`
- `source = "producer"`

然后依次发布两边：

```powershell
Set-Location ..\producer
terraform apply -auto-approve
terraform output retention_policy

Set-Location ..\consumer
terraform plan '-out=consumer-v2.tfplan'
terraform show consumer-v2.tfplan
terraform apply consumer-v2.tfplan
terraform output consumed_policy
```

Producer 只增加 state output，不创建 AWS 资源；Consumer 只原地更新一个 S3 object，最终
值为 30 天且 source 为 `producer`。

### Task 5：拒绝不兼容的合同 major

临时把 Producer 的 `retention_policy.schema_version` 改为 `2` 并 apply，再运行：

```powershell
Set-Location ..\consumer
terraform plan
```

预期结果：`aws_s3_object.consumer_manifest` 的 precondition 阻断计划，并明确说明只接受
schema version 1。把 Producer 恢复为 version 1、再次 apply，然后回到 Consumer：

```powershell
terraform plan -detailed-exitcode
```

最终退出码必须为 `0`。

## 最终验收

分别核对两份 remote state 和真实对象：

```powershell
terraform state list
terraform output consumed_policy
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c97-state `
  --key challenge97/producer.tfstate
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c97-state `
  --key challenge97/consumer.tfstate
```

Producer 和 Consumer 的 state key 必须不同；Consumer 只通过 root outputs 读合同，不能
直接依赖 Producer 的 resource address。

## 清理

按依赖反序执行：

```powershell
# challenge-97/consumer
terraform destroy -auto-approve

Set-Location ..\producer
terraform destroy -auto-approve

Set-Location ..\bootstrap
terraform destroy -auto-approve
```

删除练习产生的 plan 文件；不要提交 `.terraform`、lockfile 或 state。

## Terraform 1.6 边界

本题只使用 Terraform 1.6 已支持的 S3 backend、`terraform_remote_state.defaults`、root
outputs 和 precondition。不要使用新版 S3 lockfile、ephemeral/write-only values、
`removed` block 或 HCP Terraform；HCP 领域在当前 Pro 考试中只考选择题。
