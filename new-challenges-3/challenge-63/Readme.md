# Challenge 63：用 AWS Data Sources 组合最小权限 IAM 合同

这个练习从两个真实 LocalStack S3 buckets 开始，使用 AWS provider 的 data sources
构造 IAM trust policy 和 permissions policy。你不会手写大段 JSON，也不会把权限扩大
到通配符。

## 官方考试目标

- **2b**：Query providers using data sources
- **2c**：Compute and interpolate data using HCL functions
- 辅助使用 **2e**：Configure input variables and outputs, including complex types

考试范围参考
[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。

## 开始前

工作目录：

```powershell
Set-Location .\new-challenges-3\challenge-63
```

```powershell
curl.exe http://localhost:4566/_localstack/health
```

Starter 的起始状态：

- `bucket_names` 是包含两个名称的 `set(string)`。
- `aws_s3_bucket.scoped` 已使用普通 resource `for_each` 声明两个 buckets。
- caller identity、排序后的 bucket/object ARNs 已准备好。
- IAM policy document data sources、role、policy、attachment 和最终合同 output 都不存在。
- 所有 IAM 资源都必须由你逐步加入，starter 并未完成目标。

## Task 1：创建策略所依赖的真实资源

工作目录：`new-challenges-3/challenge-63`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply baseline.tfplan
terraform output caller_account_id
terraform output bucket_scope
```

预期结果：创建 `tfpro-c63-artifacts` 和 `tfpro-c63-logs` 两个 buckets；账号为
`000000000000`；bucket 与 object ARN 列表按字典序稳定输出。此时没有 IAM managed
resource。

## Task 2：用 data source 生成 trust policy

工作目录：`new-challenges-3/challenge-63`

添加一个 `aws_iam_policy_document` data source，地址固定为
`data.aws_iam_policy_document.assume_role`。它只允许 EC2 service principal 执行
`sts:AssumeRole`，effect 为 `Allow`。

```powershell
terraform validate
terraform plan
terraform apply -auto-approve
terraform console
```

在 console 中检查 JSON 后退出：

```text
> jsondecode(data.aws_iam_policy_document.assume_role.json)
> exit
```

预期结果：apply 只把新 data source 的读取结果写入当前 Terraform state，不新增或
修改 managed resources。console 中的文档包含一个 trust statement，不含 AWS
account principal，也没有 `Action = "*"`。

难点入口：
[AWS `aws_iam_policy_document` data source](https://registry.terraform.io/providers/hashicorp/aws/5.80.0/docs/data-sources/iam_policy_document)。

## Task 3：生成严格分离的 S3 permissions policy

工作目录：`new-challenges-3/challenge-63`

添加第二个 policy document data source，地址为
`data.aws_iam_policy_document.reader`。它必须有两个职责清晰的 statements：

1. `s3:ListBucket` 只引用 `local.bucket_arns`。
2. `s3:GetObject` 只引用 `local.object_arns`。

每个 statement 都要有稳定、可读的 `sid`。不能使用 `s3:*`、`Action = "*"` 或
`Resource = "*"`。

```powershell
terraform validate
terraform plan
terraform apply -auto-approve
terraform console
```

```text
> jsondecode(data.aws_iam_policy_document.reader.json)
> exit
```

预期结果：apply 不改变 managed resources；console 中两个 statements 的 action 和
ARN 类型正确分离，两个 bucket 及其 object 范围都被覆盖。

## Task 4：创建并连接三个 IAM resources

工作目录：`new-challenges-3/challenge-63`

依次添加：

- `aws_iam_role.reader`，名称来自 `var.role_name`，trust policy 来自 Task 2；
- `aws_iam_policy.reader`，名称为 `tfpro-c63-scoped-reader`，policy 来自 Task 3；
- `aws_iam_role_policy_attachment.reader`，把上述 policy 附加到 role。

不要把 provider block 复制进其他位置，也不要把 data source 的 JSON 重新手写一遍。

```powershell
terraform validate
terraform plan '-out=iam.tfplan'
terraform show iam.tfplan
terraform apply iam.tfplan
terraform state list
```

预期结果：plan 精确新增 1 role、1 policy、1 attachment；两个已有 buckets 不变。

## Task 5：发布可审计的结构化合同

工作目录：`new-challenges-3/challenge-63`

添加 root output `iam_contract`。它应使用 `jsondecode` 输出以下必要信息，而不是整个
resource：

- role name；
- trust policy 的结构化 statements；
- permissions policy 的结构化 statements；
- 受保护的 bucket 名列表。

再添加一个顶层 `check`，验证生成的 permissions JSON 不包含任何通配 action（包括
`s3:*` 和全局 `Action = "*"`），也不包含独立的 `Resource = "*"`。`GetObject` 所需的
bucket object ARN 仍会以 `/*` 结尾；不要错误地拒绝这种限定在指定 bucket 下的范围。
检查应针对生成结果，而不是复制一份独立的允许列表。

```powershell
terraform validate
terraform apply -auto-approve
terraform output iam_contract
terraform plan
```

预期结果：output 可直接阅读和审计；check 通过；plan 零变更。可以临时把一个 action
改成 `s3:*` 观察 warning，随后必须恢复最小权限 action。

## Task 6：证明 set 重排不改变合同

工作目录：`new-challenges-3/challenge-63`

只交换 `bucket_names` 默认列表中两个字符串的书写顺序：

```powershell
terraform fmt
terraform plan -detailed-exitcode
```

预期退出码为 `0`。如果 IAM JSON 或 resource instances 因纯重排而变化，说明你没有
使用 starter 中的稳定集合/排序边界；修复后再继续。

## 最终验收

工作目录：`new-challenges-3/challenge-63`

```powershell
terraform fmt -check
terraform validate
terraform state show aws_iam_role.reader
terraform state show aws_iam_policy.reader
terraform state show aws_iam_role_policy_attachment.reader
terraform output iam_contract
terraform plan -detailed-exitcode
```

必须满足：

- 2 buckets、1 role、1 policy、1 attachment。
- trust policy 只有 EC2 assume-role 权限。
- S3 list 与 object read 使用不同 ARN 范围，且没有全局 action/resource 通配授权。
- 重排 set 后 plan 退出码为 `0`。

## 清理

工作目录：`new-challenges-3/challenge-63`

```powershell
terraform destroy -auto-approve
Remove-Item -Force baseline.tfplan,iam.tfplan -ErrorAction SilentlyContinue
```

预期结果：attachment、policy、role 与两个 buckets 全部删除。不要提交 plan、state、
lockfile 或 `.terraform`。

## Terraform 1.6 边界

本题使用普通 provider data sources、for expressions、`jsondecode` 与 resource
`for_each`，均在 Terraform 1.6 范围内。不要使用 provider-defined functions
（Terraform 1.8+）、test mocks（1.7+）、ephemeral values、write-only arguments 或
HCP Terraform dynamic credentials。
