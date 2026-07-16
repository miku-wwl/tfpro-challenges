# Challenge 61：LocalStack 变更前的四层验证护栏

这个练习聚焦一件事：让错误尽可能在 Terraform 调用 AWS API 之前被发现。你会从一个
可以部署、但没有业务约束的 S3 配置开始，依次加入输入验证、前置条件、后置条件和
顶层检查。每一步都先观察行为，再进入下一层。

## 官方考试目标

- **2a**：Use language features to validate configuration
- **2e**：Configure input variables and outputs, including complex types
- 辅助使用 **2b**：Query providers using data sources

考试范围以 HashiCorp 的
[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
为准。

## 开始前

工作目录：

```powershell
Set-Location .\new-challenges-3\challenge-61
```

确认 LocalStack 正在运行：

```powershell
curl.exe http://localhost:4566/_localstack/health
```

Starter 只有 `Readme.md` 和 `challenge-61.tf`，并处于以下状态：

- AWS provider 已使用 `test/test` 连接 LocalStack 的 S3 和 STS endpoint。
- `bucket_spec` 是一个合法的复杂对象，但还没有任何业务 validation。
- S3 bucket 没有 precondition 或 postcondition。
- caller identity 已能读取，但还没有顶层 `check`。
- 目录中不应存在 state、lockfile、plan 文件或 `.terraform`。

不要一次写完全部条件。后面的任务依赖前一步产生的可观察行为。

## Task 1：部署无护栏基线

工作目录：`new-challenges-3/challenge-61`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform show baseline.tfplan
terraform apply baseline.tfplan
terraform output
```

预期结果：创建 1 个名为 `tfpro-c61-dev-guardrails` 的 bucket；
`caller_account_id` 为 `000000000000`。此时 Terraform 只验证类型和 provider schema，
还不会拒绝业务上不合理的 bucket 名、环境或销毁策略。

`baseline.tfplan` 是本地练习产物，不要提交到仓库。

## Task 2：在输入边界拒绝无效对象

工作目录：`new-challenges-3/challenge-61`

在 `variable "bucket_spec"` 中加入 validation，至少同时满足：

1. `name` 只含小写字母、数字、点或连字符，长度为 3～63，首尾为字母或数字。
2. `environment` 只能是 `dev`、`stage`、`prod`。
3. `prod` 环境不得启用 `force_destroy`。

先用默认值验证正常路径：

```powershell
terraform validate
terraform plan
```

再用一个无效对象验证失败路径：

```powershell
terraform plan '-var=bucket_spec={name="INVALID_NAME",environment="qa",force_destroy=false,tags={Owner="platform-team"}}'
```

预期结果：第二个命令在规划 AWS 资源前失败，并显示你编写的可操作错误信息；现有
bucket 不发生变化。恢复默认输入后，`terraform plan` 应为零变更。

难点入口：
[Input variable validation](https://developer.hashicorp.com/terraform/language/values/variables#custom-validation-rules)。

## Task 3：给资源增加前置条件

工作目录：`new-challenges-3/challenge-61`

在 `aws_s3_bucket.guarded` 的 lifecycle 中加入 precondition。它必须检查：

- bucket 名以 `tfpro-c61-<environment>-` 开头；
- 合并后的 `Owner` tag 存在且不是空字符串。

使用一个能通过 Task 2、但环境前缀不匹配的对象验证这一层：

```powershell
terraform plan '-var=bucket_spec={name="tfpro-c61-stage-guardrails",environment="dev",force_destroy=false,tags={Owner="platform-team"}}'
```

预期结果：输入 validation 通过，资源 precondition 失败；错误信息应说明名称与环境不
一致。随后重新运行默认值的 `terraform plan`，预期零变更。

## Task 4：验证 provider 返回的结果

工作目录：`new-challenges-3/challenge-61`

在同一个 lifecycle 中加入 postcondition，验证 apply/refresh 后的真实结果：

- bucket ARN 与 bucket 名相符；
- provider 返回的 `Environment` tag 与输入环境一致。

```powershell
terraform validate
terraform plan
terraform apply -auto-approve
terraform state show aws_s3_bucket.guarded
```

预期结果：已有 bucket 不应被替换；apply 后 postcondition 通过，state 中的 ARN 和
tag 符合合同。

难点入口：
[Preconditions and postconditions](https://developer.hashicorp.com/terraform/language/expressions/custom-conditions#preconditions-and-postconditions)。

## Task 5：添加不会阻断 apply 的运行环境检查

工作目录：`new-challenges-3/challenge-61`

在根模块添加一个顶层 `check`，确认 `data.aws_caller_identity.current.account_id`
等于 LocalStack account `000000000000`，并提供明确的错误信息。

```powershell
terraform validate
terraform plan
```

预期结果：正常 LocalStack 环境中 check 通过，plan 为零变更。为了观察语义，可以临时
把期望账号改为另一个 12 位数字并再次 plan：这次应出现 **warning**，而不是像
validation/precondition 那样阻断规划。观察后必须恢复 `000000000000`。

难点入口：
[`check` blocks](https://developer.hashicorp.com/terraform/language/checks)。

## 最终验收

工作目录：`new-challenges-3/challenge-61`

```powershell
terraform fmt -check
terraform validate
terraform output bucket_contract
terraform output caller_account_id
terraform state show aws_s3_bucket.guarded
terraform plan -detailed-exitcode
```

必须满足：

- 最终命令退出码为 `0`，表示零变更；不是 `2`。
- 合法默认输入通过四层检查。
- 非法 environment/name 在变量边界失败。
- 合法但命名与环境不一致的对象在 precondition 失败。
- caller account 为 `000000000000`。

## 清理

工作目录：`new-challenges-3/challenge-61`

```powershell
terraform destroy -auto-approve
Remove-Item -Force baseline.tfplan -ErrorAction SilentlyContinue
```

预期结果：bucket 被删除，destroy 完成后没有 LocalStack 资源遗留。Terraform 自动生成
的 state、lockfile 和 `.terraform` 也不得提交。

## Terraform 1.6 边界

本题只使用 Terraform 1.6 已支持的 variable validation、precondition、postcondition
和 `check`。不要添加 `.tftest.hcl`、`mock_provider`（mocking 从 1.7 才提供）、
ephemeral values 或 write-only arguments。
