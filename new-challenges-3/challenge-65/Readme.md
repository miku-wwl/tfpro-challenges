# Challenge 65：Terraform 1.6 Lifecycle Guardrails Drill

这个练习围绕同一个 `lifecycle` 主题，依次观察创建优先替换、级联替换和销毁保护。
每个规则都要通过 plan 的动作顺序来证明，不能只把 block 写进配置就算完成。

## 官方考试目标

- **2d**：Use meta-arguments in configuration
- **1b**：Generate an execution plan using `terraform plan` and its options
- **1d**：Destroy resources using `terraform destroy` and its options

考试范围参考
[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。
本题的 `random_integer` 也是官方 AWS study resources 中列出的辅助资源。

## 开始前

工作目录：

```powershell
Set-Location .\new-challenges-3\challenge-65
```

```powershell
curl.exe http://localhost:4566/_localstack/health
```

Starter 是可部署的 v1 基线：

- `random_integer.release` 用 `release_id` 作为 keeper。
- S3 object content 包含 release ID 和随机 serial。
- IAM role 名称包含 `role_revision`。
- bucket、role、object 都没有 lifecycle 规则。
- AWS provider 为 5.80.0；Random provider 固定为 3.6.3。
- 本题禁止用 `terraform_data` 替代 `random_integer`。

## Task 1：部署并记录 v1 基线

工作目录：`new-challenges-3/challenge-65`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=v1.tfplan'
terraform apply v1.tfplan
terraform output release_contract
terraform state show random_integer.release
```

预期结果：创建 1 bucket、1 object、1 role 和 1 random integer；output 中
`release_id`、role revision 都是 `v1`。记下当前 random result，用于后续比较。

## Task 2：在改名之前启用 create-before-destroy

工作目录：`new-challenges-3/challenge-65`

先在 `aws_iam_role.reader` 的 lifecycle 中加入 `create_before_destroy`，然后才把
`role_revision` 默认值从 `v1` 改成 `v2`。顺序不能颠倒。

```powershell
terraform validate
terraform plan '-out=role-v2.tfplan'
terraform show role-v2.tfplan
```

预期结果：role 必须替换，plan 使用 **create then destroy** 的 `+/-` 顺序；bucket、
object 和 random integer 不变。确认后执行：

```powershell
terraform apply role-v2.tfplan
terraform output release_contract
```

预期 role 名为 `tfpro-c65-reader-v2`。

难点入口：
[`create_before_destroy`](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#create_before_destroy)。

## Task 3：让 release 序号驱动 object 替换

工作目录：`new-challenges-3/challenge-65`

在 `aws_s3_object.release` 的 lifecycle 中加入 `replace_triggered_by`，引用
`random_integer.release`。完成规则后，把 `release_id` 默认值从 `v1` 改成 `v2`。

```powershell
terraform validate
terraform plan '-out=release-v2.tfplan'
terraform show release-v2.tfplan
```

预期结果：keeper 变化使 random integer 替换；该替换继续触发 S3 object **替换**，
而不是普通 in-place update。bucket 和 v2 role 不变。确认后执行：

```powershell
terraform apply release-v2.tfplan
terraform output release_contract
```

预期 release 为 `v2`，random serial 已重新生成。

难点入口：
[`replace_triggered_by`](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#replace_triggered_by)。

## Task 4：用 prevent-destroy 阻断全量销毁

工作目录：`new-challenges-3/challenge-65`

在 `aws_s3_bucket.releases` 的 lifecycle 中加入 `prevent_destroy = true`。先验证配置，
再生成 destroy plan；不要删除 state，也不要临时绕过规则。

```powershell
terraform validate
terraform plan -destroy
```

预期结果：第二个命令以非零退出码失败，并明确指出受保护的 bucket。失败是本任务的
验收结果；LocalStack 中所有资源仍存在。

难点入口：
[`prevent_destroy`](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#prevent_destroy)。

## Task 5：用 `-replace` 演练一次受控重新生成

工作目录：`new-challenges-3/challenge-65`

保持 `release_id = "v2"`，显式要求重新生成 random integer，并保存计划：

```powershell
terraform plan '-replace=random_integer.release' '-out=reroll.tfplan'
terraform show reroll.tfplan
```

预期结果：random integer 被替换；由于 Task 3 的规则，release object 也被替换；
bucket 与 IAM role 不变。确认范围后只应用该 saved plan：

```powershell
terraform apply reroll.tfplan
terraform output release_contract
```

不要依赖随机数一定不同来评分；关键证据是 plan 的 replacement actions 和新的
resource instance 生命周期。

## Task 6：确认三条规则互不冲突

工作目录：`new-challenges-3/challenge-65`

```powershell
terraform fmt -check
terraform validate
terraform state show aws_iam_role.reader
terraform state show random_integer.release
terraform state show aws_s3_object.release
terraform output release_contract
terraform plan -detailed-exitcode
```

预期最后退出码为 `0`；release 和 role revision 都为 `v2`。配置中应保留三条
lifecycle 规则，且没有为了通过实验而增加无关资源。

## 最终验收

必须同时满足：

- role v1→v2 的 plan 显示 create-before-destroy。
- release v1→v2 时 random integer 和 S3 object 都显示 replacement。
- bucket 阻断 `plan -destroy`，远端资源未被误删。
- `-replace=random_integer.release` 的 saved plan 不包含 bucket/role 变更。
- 正常完整 plan 最终为零变更。

## 清理

工作目录：`new-challenges-3/challenge-65`

`prevent_destroy` 会阻止清理。先从 bucket lifecycle 中移除该参数，再审阅并执行：

```powershell
terraform plan -destroy
terraform destroy -auto-approve
Remove-Item -Force v1.tfplan,role-v2.tfplan,release-v2.tfplan,reroll.tfplan -ErrorAction SilentlyContinue
```

预期结果：object、bucket、role 和 random integer 全部从 state 移除。不得使用
`terraform state rm` 绕过保护，也不要提交任何生成文件。

## Terraform 1.6 边界

本题只使用 Terraform 1.6 已支持的 `create_before_destroy`、`replace_triggered_by`、
`prevent_destroy`、saved plan 和 `-replace`。明确禁止 `terraform_data`、`removed`
block（1.7+）、`action_trigger`、ephemeral values、write-only arguments 以及脚本。
