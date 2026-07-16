# Challenge 77：Module Calls 从静态地址迁移到稳定 `for_each`

根模块当前用 `module.api` 和 `module.worker` 两次调用同一个 child module。
你要把重复调用收敛为一个 `for_each` module call，并用声明式 `moved` blocks
迁移地址。两只已经存在的 LocalStack buckets 必须保留，不能重建。

## 考纲定位

- **4c** Refactor a module and use module versioning concepts
- **4d** Refactor an existing configuration into modules
- **1e** Manage resource state with declarative moves
- 辅助考点：**2d** module `for_each`

本题使用 Terraform 1.6 的 module `for_each` 和 `moved` blocks；不会使用
Terraform 1.7 的 `removed` block 或 import `for_each`。

## 起始结构与基线

```text
challenge-77/
├── challenge-77.tf
├── modules/release/main.tf
└── Readme.md
```

在 `new-challenges-3/challenge-77` 中执行：

```powershell
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
terraform init
terraform validate
terraform apply -auto-approve
terraform state list
```

Terraform 必须是 1.6.x，LocalStack 的 S3 服务必须可用。

起始 state 必须包含：

```text
module.api.aws_s3_bucket.this
module.worker.aws_s3_bucket.this
```

分别记录两个 bucket ID：

```powershell
terraform state show module.api.aws_s3_bucket.this
terraform state show module.worker.aws_s3_bucket.this
```

## 任务

### Task 1：建立重构前的安全检查点

先保存一份只读 state 快照到 challenge 目录之外；该文件只是练习过程备份，
不得提交：

```powershell
terraform state pull | Out-File -Encoding utf8 ..\challenge-77-before.json
terraform plan
```

plan 必须为 `No changes`。如果基线本身不干净，先不要重构。

### Task 2：把两次调用的数据收敛成稳定 map

修改 `challenge-77.tf`，创建一个 map，key 必须固定为 `api`、`worker`，每个
value 包含当前的 `bucket_name` 和 `owner`。key 是未来的 state identity，不能用
列表下标代替。

随后用一个名为 `release` 的 module call 取代 `module.api` 与
`module.worker`：

- `for_each` 使用该 map。
- `bucket_name` 和 `owner` 从 `each.value` 读取。
- module source 仍为 `./modules/release`。

更新 output，使它从新的 module instances 生成同样的 api/worker map。此时只运行：

```powershell
terraform fmt -recursive
terraform init
terraform validate
terraform plan
```

module call 地址改变后必须先重新 `init` 安装新调用；然后 plan 预计错误地显示
2 destroy + 2 create，因为此时还没有 move 声明。
这是教学性检查，**不要 apply**。

### Task 3：声明两个 whole-module moves

在根目录任意 `.tf` 文件中加入两个 `moved` blocks，精确表达：

| 旧 module address | 新 module address |
| --- | --- |
| `module.api` | `module.release["api"]` |
| `module.worker` | `module.release["worker"]` |

PowerShell 命令中的带引号地址应整体放进单引号，例如：

```powershell
terraform state show 'module.release["api"].aws_s3_bucket.this'
```

本题禁止用 `terraform state mv` 代替 moved blocks；团队需要能在 code review 中
看到这条升级路径。

### Task 4：用零资源动作计划验收迁移

```powershell
terraform plan '-out=module-move.tfplan'
terraform show module-move.tfplan
```

计划可以显示两个地址 moved，但摘要必须是：

```text
Plan: 0 to add, 0 to change, 0 to destroy.
```

如果出现 replace，通常是新 map 中的 bucket name 或 owner 与 baseline 不一致；
修正输入后再继续。

### Task 5：应用地址迁移并核对物理 ID

```powershell
terraform apply module-move.tfplan
terraform state list
terraform state show 'module.release["api"].aws_s3_bucket.this'
terraform state show 'module.release["worker"].aws_s3_bucket.this'
```

旧地址应消失，新地址应出现；两个 bucket ID 必须与 Task 1 记录完全相同。
删除运行时 saved plan：

```powershell
Remove-Item -LiteralPath .\module-move.tfplan
```

### Task 6：证明源码重排不会扰动 state

交换 map 中 `api` 和 `worker` 的书写顺序，再运行 `terraform plan`。因为实例由
稳定 key 标识，结果必须为 `No changes`。保留两个 moved blocks，它们记录了
旧版本到新版本的兼容路径。

## 最终验收

- state 只包含 `module.release["api"]` 和 `module.release["worker"]` 下的资源。
- 两只 bucket 的物理 ID 没有改变。
- `moved` blocks 留在配置中，plan 为 `No changes`。
- 调整 map 源码顺序不会产生资源动作。
- 未使用手工 `state mv`，未提交 state backup 或 saved plan。

## 清理

```powershell
terraform destroy -auto-approve
```

清理后可删除 challenge 目录外的临时备份。参考：[Refactor modules](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring)、[`moved` block](https://developer.hashicorp.com/terraform/language/moved)。
