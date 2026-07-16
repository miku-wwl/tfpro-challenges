# Challenge 86：Conditional `count` 与类型稳定的 Nullable Output

这一题从一个可以正常部署的可选审计 Bucket 开始。默认输入为 `true`，所以 starter 中
直接读取 `[0]` 暂时不会报错；当你关闭功能时，这个脆弱合同才会暴露。你要用
`one()` 与 full splat 把“零个或一个实例”收敛成 `string` 或 `null`，同时保持 output
对象的字段形状不变。

## 学习目标

- 解释 conditional `count` 为什么会让资源地址集合变成零个或一个实例；
- 用 `one()` 与 full splat 表达真正的 nullable value，而不是伪造占位字符串；
- 从 plan、state、output 与 S3 API 四个视角验证可选资源合同。

## 考纲定位

- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types
- 辅助使用 **1b / 1c**：审阅并应用条件资源变更

本题只使用 Terraform 1.6、AWS Provider 5.80.0 和 LocalStack S3。不要使用
`try(..., "")`、空字符串、假 Bucket 名或第二个重复 output 来掩盖“资源不存在”。

## 开始前

打开专用 PowerShell，进入本题目录：

```powershell
Set-Location .\new-challenges-4\challenge-86
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

Starter 只有 `Readme.md` 和 `challenge-86.tf`，默认配置完整可运行。后续任务必须按顺序
完成；Task 2 的失败是理解问题边界所必需的证据。

## 任务

### Task 1：部署启用状态的完整基线

工作目录：`new-challenges-4/challenge-86`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=enabled.tfplan'
terraform apply enabled.tfplan
terraform state list
terraform output -json audit_contract
```

预期 state 只有 `aws_s3_bucket.audit[0]`。合同中的 `enabled` 为 `true`，`bucket` 为
`tfpro-challenge86-audit`。用 LocalStack API 再核验一次：

```powershell
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-challenge86-audit
```

### Task 2：观察直接索引在零实例时失败

不要先修改 output。仅关闭开关并生成计划：

```powershell
terraform plan '-var=enable_audit=false'
```

这是预期失败。`count = 0` 后资源 tuple 为空，`aws_s3_bucket.audit[0].id` 会产生
`Invalid index`。不要通过保持 `count = 1`、硬编码 Bucket 名或捕获任意错误来绕过。

### Task 3：用 `one()` 建立类型稳定合同

修改 `audit_contract`，保留 `enabled`、`bucket` 两个字段，但让 `bucket` 使用：

```hcl
one(aws_s3_bucket.audit[*].id)
```

full splat 在本题只可能产生零个或一个字符串，`one()` 因而返回 Bucket ID 或真正的
`null`。完成后运行：

```powershell
terraform fmt
terraform validate
terraform plan '-var=enable_audit=false' '-out=disabled.tfplan'
terraform show disabled.tfplan
```

预期只删除 `aws_s3_bucket.audit[0]`；output 仍是相同对象形状，其中 `bucket` 从字符串
变为 `null`。

### Task 4：应用关闭状态并同时核验 State 与 API

```powershell
terraform apply disabled.tfplan
terraform state list
terraform output -json audit_contract
aws --endpoint-url=http://localhost:4566 s3api list-buckets `
  --query "Buckets[?Name=='tfpro-challenge86-audit'].Name"
```

预期 state 不再包含 managed resource，output 仍存在且精确为“enabled=false、bucket=null”；
API 查询返回空列表。

### Task 5：重新启用同一可选实例

```powershell
terraform plan '-var=enable_audit=true' '-out=re-enabled.tfplan'
terraform show re-enabled.tfplan
terraform apply re-enabled.tfplan
terraform state show 'aws_s3_bucket.audit[0]'
terraform output -json audit_contract
```

预期地址仍是 `aws_s3_bucket.audit[0]`，合同自动回到字符串值。不要为启用和关闭分别创建
两套 resources 或 outputs。

### Task 6：证明最终配置已收敛

```powershell
terraform fmt -check
terraform validate
terraform plan -detailed-exitcode '-var=enable_audit=true'
$LASTEXITCODE
```

退出码必须为 `0`，不是表示有变更的 `2`。

## 清理

```powershell
terraform destroy -auto-approve '-var=enable_audit=true'
Remove-Item .\enabled.tfplan,.\disabled.tfplan,.\re-enabled.tfplan `
  -Force -ErrorAction SilentlyContinue
```

销毁后 `terraform state list` 为空，LocalStack 中没有本题 Bucket。不要提交
`.terraform/`、lockfile、state 或 saved plan。

## Terraform 1.6 边界

本题只使用 Terraform 1.6 已支持的 resource `count`、full splat、`one()` 和 nullable
值传播。Output block 在 Terraform 1.6 没有显式 `type` argument；这里的“类型稳定”指
对象字段集合始终相同，只有 `bucket` 在 `string` 与 `null` 之间切换。
