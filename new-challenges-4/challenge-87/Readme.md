# Challenge 87：EC2 `count` 地址迁移到业务键 `for_each`

Starter 使用 `count` 创建 `api` 与 `worker` 两台 LocalStack EC2 instances，state 地址
由数字索引标识。你要先部署并记录物理 ID，再把配置改为业务键 `for_each`，使用两个
声明式 `moved` blocks 完成零替换迁移。只改 HCL 不等于迁移 state；没有 move 声明的
destroy/create 计划绝不能 apply。

## 学习目标

- 区分资源参数相同与 Terraform instance address 相同；
- 用静态 `moved` blocks 把数字索引安全迁移到稳定业务键；
- 用零动作计划、state 地址、物理 ID 与 EC2 API 共同证明没有重建。

## 考纲定位

- **1e**：Manage resource state and preserve existing infrastructure
- **2d**：Use `count`, `for_each`, and `moved` configuration
- 辅助使用 **1b / 1c**：审阅并应用零动作迁移计划

## 开始前

```powershell
Set-Location .\new-challenges-4\challenge-87
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

本题固定使用 LocalStack 内置 AMI `ami-04681a1dbd79675a5`。不要把 endpoint 删除后连接
真实 AWS。Starter 是完整的 count 基线，必须先 apply 再重构。

## 任务

### Task 1：部署并记录数字索引基线

工作目录：`new-challenges-4/challenge-87`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=count-baseline.tfplan'
terraform apply count-baseline.tfplan
terraform state list
terraform output -json fleet_contract
```

state 必须包含：

```text
aws_instance.node[0]
aws_instance.node[1]
```

把两个 ID 保存在当前 PowerShell 变量中，后续用来证明没有重建：

```powershell
$before = terraform output -json fleet_contract | ConvertFrom-Json
$apiBefore = $before.api.id
$workerBefore = $before.worker.id
```

### Task 2：先观察“只改地址”的错误计划

将 `local.node_names` 改为以 `api`、`worker` 为 key 的 map，并把同一个
`aws_instance.node` 改成：

- `for_each = local.nodes`；
- Name 与 Service tags 从 `each.key` / `each.value` 读取；
- output 从新实例 map 生成相同的 `api` / `worker` 合同。

此时不要添加 moved blocks，先运行：

```powershell
terraform fmt
terraform validate
terraform plan
```

预期错误计划显示两个旧数字地址删除、两个新业务键地址创建。真实实例参数虽然相同，
Terraform 仍把不同地址视为不同实例。停止，不要 apply。

> **Note（☆）**：`for_each` 创建的 resource 实例集合是 map，可以像普通 map 一样使用
> `for key, value in aws_instance.node` 遍历；`key` 是 `api`/`worker`，`value` 是对应的
> resource instance。使用 `count` 时集合按数字索引组织，通常使用
> `for index, instance in aws_instance.node`。因此：`for_each resource → map → key/value`，
> `count resource → tuple → index/value`。

### Task 3：声明两条精确地址迁移

在根模块加入两个静态 `moved` blocks：

| From | To |
| --- | --- |
| `aws_instance.node[0]` | `aws_instance.node["api"]` |
| `aws_instance.node[1]` | `aws_instance.node["worker"]` |

不能使用 `terraform state mv`、import、target、state rm 或 destroy/recreate 代替。

### Task 4：生成零远端动作的迁移计划

```powershell
terraform fmt -check
terraform validate
terraform plan '-out=address-migration.tfplan'
terraform show address-migration.tfplan
```

计划应显示两个 `has moved to`，摘要必须是：

```text
Plan: 0 to add, 0 to change, 0 to destroy.
```

只要出现 update、replace、create 或 delete，就应检查 map 中的 Name/Service 值与基线是否
逐字相同，不能继续。

### Task 5：应用地址迁移并核验物理 ID

```powershell
terraform apply address-migration.tfplan
terraform state list
terraform output -json fleet_contract
```

新地址必须是：

```text
aws_instance.node["api"]
aws_instance.node["worker"]
```

比较前后 ID，并从 EC2 API 验证同两台 instances：

```powershell
$after = terraform output -json fleet_contract | ConvertFrom-Json
$after.api.id -eq $apiBefore
$after.worker.id -eq $workerBefore
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $apiBefore $workerBefore `
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Service`].Value|[0]]'
```

两个布尔比较都必须为 `True`，API 中 service 分别为 `api`、`worker`。

### Task 6：证明源码顺序不再决定身份

只交换 `local.nodes` 中 `api` 与 `worker` 的书写顺序，不修改任何值：

```powershell
terraform fmt
terraform plan -detailed-exitcode
$LASTEXITCODE
```

退出码必须为 `0`。保留 moved blocks，它们是旧 state 升级到新地址的可审计路径。

## 清理

```powershell
terraform destroy -auto-approve
terraform state list
Remove-Item .\count-baseline.tfplan,.\address-migration.tfplan `
  -Force -ErrorAction SilentlyContinue
```

不得提交 state、plan、lockfile 或 `.terraform`。

## Terraform 1.6 边界

Terraform 1.6 支持 resource `for_each` 与静态 moved blocks，但不能动态生成 moved blocks。
本题不使用 Terraform 1.7 的 `removed` block 或 import `for_each`。
