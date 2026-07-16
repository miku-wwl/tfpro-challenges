# Challenge 69：单体 IAM 配置到 Child Module 的零替换迁移

## 题目目标

starter 是一份可工作的单体 IAM 配置，没有预建 module 目录。你必须先部署它，再创建
child module、设计输入输出，并使用 `moved` blocks 把三个既有资源迁到模块地址。
第一次迁移 plan 只能更新地址，不能调用远端 API 创建、更新或销毁资源。

考纲对应：module 创建与调用、输入输出合同、state 地址、moved block 与零替换重构。

## 开始前检查

在 `new-challenges-3/challenge-69` 中执行。不要提前创建 `modules`，也不要在初始 apply 前
修改 resource 地址：

```powershell
Invoke-RestMethod http://localhost:4566/_localstack/health
terraform init
terraform validate
terraform plan '-out=monolith.tfplan'
terraform apply monolith.tfplan
terraform state list
```

预期创建一个 role、一个 managed policy 和一个 attachment。两个
`aws_iam_policy_document` data source 也可能显示在 state；本题迁移的是三个 managed
resource 地址。

## Task 1：保存重构前证据

先确认初始配置幂等，并备份 state：

```powershell
terraform plan
terraform state show aws_iam_role.workload
terraform state show aws_iam_policy.workload
terraform state show aws_iam_role_policy_attachment.workload
terraform state pull | Out-File -FilePath .\before-refactor.tfstate.json -Encoding utf8
```

预期普通 plan 为 `No changes`。state 备份只用于本题恢复与对照，不得手工编辑后 push。

## Task 2：创建 child module 合同

现在才在本题目录下创建以下 Terraform 文件：

```text
modules/identity/main.tf
modules/identity/variables.tf
modules/identity/outputs.tf
modules/identity/versions.tf
```

完成这些要求：

1. 把三个 managed resource blocks 移入 `modules/identity/main.tf`，资源标签仍叫 `workload`。
2. module 输入至少包含 role name、policy name、两个 policy JSON 字符串和 tags。
3. module 输出 role ARN 与 policy ARN；root 的 `identity_contract` 继续保持原有形状和值。
4. child module 只声明 AWS provider requirement，不得包含 `provider "aws"` 配置。
5. root 创建 `module "identity"`，显式传入当前默认 AWS provider 和两个 data source 的 JSON。

完成模块文件和 root 调用后依次运行 `terraform fmt -recursive`、`terraform init` 与
`terraform validate`，但此时不要 apply。新增本地 module 后必须先由 `init` 安装它；仅移动
HCL 不会自动告诉 Terraform 旧地址与新地址是同一个对象。

官网入口：[Build modules](https://developer.hashicorp.com/terraform/language/modules/develop)。

## Task 3：声明三个静态地址迁移

在 root 新建 `moved.tf`，为下列每一行建立一个 `moved` block：

| 旧地址 | 新地址 |
| --- | --- |
| `aws_iam_role.workload` | `module.identity.aws_iam_role.workload` |
| `aws_iam_policy.workload` | `module.identity.aws_iam_policy.workload` |
| `aws_iam_role_policy_attachment.workload` | `module.identity.aws_iam_role_policy_attachment.workload` |

`from` 和 `to` 必须是静态资源地址；不要使用 `terraform state mv`、import、删除 state 或
销毁重建来代替声明式迁移。

官网入口：[Refactor modules with moved blocks](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring)。

## Task 4：审阅并应用零替换迁移

```powershell
terraform init
terraform validate
terraform plan '-out=migration.tfplan'
terraform show -no-color migration.tfplan
```

预期 plan 为 `0 to add, 0 to change, 0 to destroy`，并明确显示三个地址 `has moved to`。
如果出现 create、update、delete 或 replace，停止并检查 module 参数是否与原属性完全一致；
不要 apply 有远端动作的迁移计划。

满足零动作条件后：

```powershell
terraform apply migration.tfplan
terraform state list
terraform plan
terraform output identity_contract
```

预期三个旧 managed 地址消失，三个 `module.identity...` 地址出现；最终普通 plan 为
`No changes`，两个 ARN 与重构前一致。

## Task 5：清理

```powershell
terraform destroy -auto-approve
terraform state list
Remove-Item .\monolith.tfplan,.\migration.tfplan,.\before-refactor.tfstate.json -ErrorAction SilentlyContinue
```

预期 state 为空，LocalStack 中不再存在本题 role、policy 或 attachment。

## Terraform 1.6 边界

- `moved` block 是配置中的静态迁移记录，可以在重构后保留供旧 state 升级。
- Terraform 1.6 不支持用表达式动态生成 `moved` blocks，也不使用后续版本的 `removed` block。
- Provider configuration 属于 root；可复用 child module 只声明 requirement 并接收调用方映射。

## 最终检查

- 单体配置先成功 apply，并保存了重构前 state 证据。
- starter 的三个资源全部进入 `module.identity`，接口与输出清楚。
- migration plan 只有三个地址移动，没有任何远端动作。
- apply 后旧地址消失、ARN 不变、普通 plan 干净。
