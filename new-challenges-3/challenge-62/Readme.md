# Challenge 62：无外部清单的 HCL Collection Pipeline

这个练习只使用一个内联的复杂变量，把团队目录逐层转换成稳定的 S3 object 实例。
重点不是堆叠函数，而是让每一层都有明确的输入、输出和可验证结果。

## 官方考试目标

- **2c**：Compute and interpolate data using HCL functions
- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types

考试范围参考
[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。

## 开始前

工作目录：

```powershell
Set-Location .\new-challenges-3\challenge-62
```

```powershell
curl.exe http://localhost:4566/_localstack/health
```

Starter 的状态：

- `teams` 是 `map(object(...))`，包含启用的 `api`、`worker` 和禁用的 `legacy`。
- 启用团队合计声明 3 个 path。
- 一个空的 S3 bucket 配置已经存在。
- 四个 locals 仍为空；没有 `aws_s3_object`，也没有最终 manifest output。
- 不使用 JSON、CSV、template、tfvars 或脚本。

## Task 1：部署空 bucket 基线

工作目录：`new-challenges-3/challenge-62`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply baseline.tfplan
terraform output
```

预期结果：只创建 `aws_s3_bucket.artifacts`；`enabled_team_names` 和
`artifact_keys` 都是空集合。不要在这一阶段创建 objects。

## Task 2：过滤启用的团队

工作目录：`new-challenges-3/challenge-62`

用带过滤子句的 map for expression 替换 `local.enabled_teams` 的空值。map 的 key
必须继续使用原团队名，不能改成数字索引。

```powershell
terraform validate
terraform plan
terraform apply -auto-approve
terraform output enabled_team_names
```

预期结果：output 只包含 `api`、`worker`；`legacy` 不出现。此步只有 root output
变化，不新增 AWS 资源。

难点入口：
[For expressions](https://developer.hashicorp.com/terraform/language/expressions/for)。

## Task 3：合并默认与团队 tags

工作目录：`new-challenges-3/challenge-62`

构造 `local.normalized_teams`。每个启用团队必须保留 paths，并使用 `merge` 合并
`var.global_tags` 与团队 tags；同名 key 由团队值覆盖。

```powershell
terraform validate
terraform console
```

在 console 中检查后退出：

```text
> local.normalized_teams
> exit
```

预期结果：只有两个团队；每个团队同时拥有 `ManagedBy`、`Course`、`Owner`、`Tier`，
而 `Owner`/`Tier` 保持团队自己的值。此步不产生基础设施变更。

难点入口：
[`merge` function](https://developer.hashicorp.com/terraform/language/functions/merge)。

## Task 4：展开行并生成稳定业务 key

工作目录：`new-challenges-3/challenge-62`

按两个小步骤完成：

1. 使用嵌套 for expression 和 `flatten`，让每个 team/path 成为一个扁平对象。
2. 把扁平列表转成 map，以 `team/path` 作为唯一 key，赋给
   `local.artifact_instances`。

每个实例至少要携带 team、path 和合并后的 tags。不能使用列表下标作为资源身份。

```powershell
terraform validate
terraform plan
terraform apply -auto-approve
terraform output artifact_keys
```

预期结果：`artifact_keys` 精确包含 3 个稳定 key；仍然没有新增 AWS object，因为
resource block 要到下一步才添加。

难点入口：
[`flatten` function](https://developer.hashicorp.com/terraform/language/functions/flatten)。

## Task 5：用一个 resource block 发布三个 objects

工作目录：`new-challenges-3/challenge-62`

添加一个 `aws_s3_object` resource，以 `local.artifact_instances` 作为 `for_each`：

- remote key 使用与 resource instance 相同的稳定 `team/path` 业务 key；
- content 使用 `jsonencode`，至少包含 team、path、tags；
- content type 为 `application/json`；
- 不得复制三个 resource block。

再添加结构化 `artifact_manifest` output，以稳定业务 key 为索引，公开 bucket、remote
key 和 owner；不要输出整个 provider resource object。

```powershell
terraform validate
terraform plan '-out=objects.tfplan'
terraform show objects.tfplan
terraform apply objects.tfplan
terraform state list
terraform output artifact_manifest
```

预期结果：plan 精确新增 3 个 `aws_s3_object`；state 中三个实例地址均含可读的业务
key；manifest 精确有 3 项。

难点入口：
[`for_each`](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each) 和
[`jsonencode`](https://developer.hashicorp.com/terraform/language/functions/jsonencode)。

## Task 6：证明重排不会改变资源身份

工作目录：`new-challenges-3/challenge-62`

只重排 `teams` map 中 block 的书写顺序，以及 `api.paths` 的书写顺序，不改变任何
业务值。

```powershell
terraform fmt
terraform plan -detailed-exitcode
```

预期退出码为 `0`，且无资源地址变化。随后临时把一个 path 改成新值：plan 应只显示
旧 object 删除、新 object 创建。不要 apply 这个试验；恢复原 path 后再次确认零变更。

## 最终验收

工作目录：`new-challenges-3/challenge-62`

```powershell
terraform fmt -check
terraform validate
terraform state list
terraform output enabled_team_names
terraform output artifact_keys
terraform output artifact_manifest
terraform plan -detailed-exitcode
```

必须满足：

- 1 个 bucket、3 个 objects，禁用团队不创建任何实例。
- resource 使用稳定 `team/path` key，而不是 `count` 或列表位置。
- manifest 有序且只公开所需合同。
- 输入重排后 plan 退出码为 `0`。

## 清理

工作目录：`new-challenges-3/challenge-62`

```powershell
terraform destroy -auto-approve
Remove-Item -Force baseline.tfplan,objects.tfplan -ErrorAction SilentlyContinue
```

预期结果：三个 objects 先删除，bucket 随后删除。不要提交 Terraform 生成文件。

## Terraform 1.6 边界

本题只在普通 resource 上使用 `for_each`。不要把 `for_each` 加到 import block（该
能力属于 Terraform 1.7），也不要使用 provider-defined functions、test mocks、
ephemeral values 或任何外部数据文件。
