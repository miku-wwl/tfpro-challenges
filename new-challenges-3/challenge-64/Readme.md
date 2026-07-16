# Challenge 64：依赖闭包与一次安全的 Targeted Apply

这个练习让你区分两类依赖：表达式已经建立的隐式依赖，以及业务顺序需要、但表达式
看不出来的显式依赖。完成依赖图后，你会执行一次有明确恢复范围的 targeted apply，
再回到完整 Terraform workflow。

## 官方考试目标

- **2d**：Use meta-arguments in configuration
- **1b**：Generate an execution plan using `terraform plan` and its options
- **1c**：Apply configuration changes using `terraform apply` and its options

HashiCorp Professional learning path 明确要求理解 resource targeting；详细范围见
[Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。

## 开始前

工作目录：

```powershell
Set-Location .\new-challenges-3\challenge-64
```

```powershell
curl.exe http://localhost:4566/_localstack/health
```

Starter 已声明 bucket、IAM reader role/policy/attachment、`ready` marker 和独立的
`notes` object，但目录中没有 state。关键起始缺口是：

- ARN、role name、policy ARN、bucket ID 的引用已经建立隐式边。
- `ready` 的 content 是常量，Terraform 看不出“先完成 policy attachment，再发布
  ready marker”的业务顺序。
- `ready` 尚未包含这条显式依赖；不要在 Task 1 前 apply。

## Task 1：阅读现有隐式依赖

工作目录：`new-challenges-3/challenge-64`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform graph
terraform plan
```

预期结果：配置有效，完整 plan 显示 6 个 managed resources 待创建。你应能从引用中
识别：objects 依赖 bucket、policy 依赖 bucket、attachment 依赖 role 和 policy。
但是 `ready` 没有指向 attachment 的边。

不要为已有引用的所有资源添加冗余 `depends_on`。

## Task 2：只添加缺失的业务依赖

工作目录：`new-challenges-3/challenge-64`

在 `aws_s3_object.ready` 中添加一个 `depends_on`，目标只能是
`aws_iam_role_policy_attachment.reader`。不要让 `notes` 依赖 IAM，也不要把 bucket、
role、policy 重复列入该列表。

```powershell
terraform validate
terraform graph
terraform plan
```

预期结果：plan 的资源数量没有变化，但图中 ready marker 现在位于 attachment 的下游。

难点入口：
[`depends_on`](https://developer.hashicorp.com/terraform/language/meta-arguments/depends_on)。

## Task 3：生成并审阅 targeted plan

工作目录：`new-challenges-3/challenge-64`

这是范围受限操作。先保存 plan，禁止直接跳过审阅 apply：

```powershell
terraform plan '-target=aws_s3_object.ready' '-out=ready.tfplan'
terraform show ready.tfplan
```

预期结果：managed resource 摘要为 **5 to add**：bucket、role、policy、attachment、
ready marker。`aws_s3_object.notes` 不应出现在 saved plan 中。Terraform 会显示 targeted
planning 警告，这是预期行为。

如果 plan 只有 bucket 和 ready，说明 Task 2 的显式边没有正确建立，不能 apply。

难点入口：
[`terraform plan -target`](https://developer.hashicorp.com/terraform/cli/commands/plan#resource-targeting)。

## Task 4：只应用已审阅的恢复计划

工作目录：`new-challenges-3/challenge-64`

```powershell
terraform apply ready.tfplan
terraform state list
terraform state show aws_s3_object.ready
```

预期结果：Task 3 的五个 managed resources 已进入 state；
`aws_s3_object.notes` 地址不存在。apply 结束时可能再次提醒结果不完整，这是 target
workflow 的正常警告。

不要手动编辑 state，也不要运行第二个 target 去逐个补资源。

## Task 5：回到完整 plan/apply workflow

工作目录：`new-challenges-3/challenge-64`

```powershell
terraform plan '-out=full.tfplan'
terraform show full.tfplan
terraform apply full.tfplan
```

预期结果：完整 plan 只新增 `aws_s3_object.notes`，摘要为 **1 to add**；已经 targeted
apply 的五个 managed resources 不发生变化。

## Task 6：验证完整依赖状态

工作目录：`new-challenges-3/challenge-64`

```powershell
terraform state list
terraform output release_contract
terraform plan -detailed-exitcode
```

预期退出码为 `0`。此时才能认为恢复操作完成。`-target` 适合异常恢复或排障，不应
成为日常发布时绕过完整 plan 的方法。

## 最终验收

工作目录：`new-challenges-3/challenge-64`

```powershell
terraform fmt -check
terraform validate
terraform state show aws_iam_role_policy_attachment.reader
terraform state show aws_s3_object.ready
terraform state show aws_s3_object.notes
terraform plan -detailed-exitcode
```

必须满足：

- 6 个 managed resources 均存在。
- ready marker 明确依赖 attachment，notes 不含无关显式依赖。
- targeted 阶段没有提前创建 notes。
- full workflow 补齐 notes 后，最终 plan 退出码为 `0`。

## 清理

工作目录：`new-challenges-3/challenge-64`

```powershell
terraform destroy -auto-approve
Remove-Item -Force ready.tfplan,full.tfplan -ErrorAction SilentlyContinue
```

预期结果：两个 objects、IAM resources 和 bucket 全部删除。不要提交生成的 plan、
state、lockfile 或 `.terraform`。

## Terraform 1.6 边界

本题只使用 Terraform 1.6 已支持的 `depends_on`、`-target` 和 saved plan。不要加入
新版 `action_trigger`、HCP Terraform run triggers、动态 provider 配置、test mocks
或脚本。target 本身在大纲内，但必须保持异常路径语义。
