# Challenge 26：为类型化 S3 合同建立四层验证

平台团队已有一个类型正确的 bucket contract，但“类型正确”还不足以阻止错误环境、空 owner
或名称与环境不一致。你将依次添加 input validation、resource precondition、resource
postcondition 和非阻塞 `check`，并观察它们在 plan/apply 中不同的失败语义。

## 官方考试目标

- **2a**：Use language features to validate configuration
- **2e**：Configure input variables and outputs, including complex types

本题使用 `aws_s3_bucket` 与 `data.aws_caller_identity`。`check`、precondition 和
postcondition 都在 Terraform 1.6 考试边界内；不要改用 Terraform test mock provider。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-26
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

目录只有 `Readme.md` 和 `challenge-26.tf`。Starter 已包含：

- AWS provider `5.80.0`，S3 和 STS 指向 LocalStack；
- 类型为 object 的 `bucket_contract`，但没有 validation block；
- `expected_account_id` 与 caller identity 查询；
- bucket `tfpro-c26-dev-validated`，但没有 lifecycle conditions 或 check。

## Task 1：运行“类型正确但约束不足”的基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply .\baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
terraform output -json validation_baseline | ConvertFrom-Json
```

应创建 1 个 bucket，account ID 通常为 `000000000000`。注意 `terraform validate` 成功只说明
当前 HCL 和类型有效，还没有证明业务合同完整。

## Task 2：给复杂输入添加业务 validation

在 `bucket_contract` 中添加一个或多个 validation block，精确满足：

- name 必须以 `tfpro-c26-` 开头，且总长度不超过 63；
- environment 只能是 `dev`、`stage`、`prod`；
- 对 owner 执行 `trimspace` 后不能是空字符串；
- 每种失败必须有对人有用的 `error_message`。

```powershell
terraform fmt
terraform validate
terraform plan '-var=bucket_contract={name=\"wrong-name\",environment=\"qa\",owner=\"\"}'
```

计划必须在读取或修改 AWS 对象前因变量验证失败，并显示你编写的消息。默认合同仍应有效：

```powershell
terraform plan
```

## Task 3：用 precondition 检查跨字段关系

在 `aws_s3_bucket.validated` 的 lifecycle 中添加 precondition：规范化后的 bucket name 必须
包含 `-${var.bucket_contract.environment}-`。这个关系依赖两个字段，不应重复塞进 type constraint。

```powershell
terraform fmt
terraform validate
terraform plan '-var=bucket_contract={name=\"tfpro-c26-dev-mismatch\",environment=\"prod\",owner=\"platform\"}'
```

输入的每个单独字段都合法，但组合不合法；plan 应以 precondition 的自定义消息失败。默认
合同的 plan 应继续显示 `No changes`。

## Task 4：用 postcondition 验证 provider 返回结果

在同一个 lifecycle block 中添加 postcondition，至少验证：

- provider 返回的 bucket 标识等于规范化名称；
- 返回标签中的 `Environment` 等于合同环境。

postcondition 必须通过 `self` 引用当前资源，不能把它写成另一个 input validation。

```powershell
terraform fmt
terraform validate
terraform plan '-out=conditions.tfplan'
terraform apply .\conditions.tfplan
Remove-Item -LiteralPath .\conditions.tfplan
terraform plan
```

默认合同应通过，且不会重建现有 bucket。

## Task 5：添加一个不阻塞运行的全局 `check`

添加名为 `localstack_account` 的 check block，断言 caller account ID 等于
`var.expected_account_id`，并给出明确 warning。先验证成功路径，再故意传错期望值：

```powershell
terraform fmt
terraform validate
terraform plan
terraform plan '-var=expected_account_id=111111111111'
$LASTEXITCODE
```

错误期望值应产生 `Check block assertion failed` warning，但计划仍完成，退出码应为 `0`。
这与 variable validation 和 precondition 的阻塞失败不同。不要用 check 保护必须阻止的约束。

## Task 6：联合验收并清理

```powershell
terraform apply -auto-approve
terraform output -json validation_baseline | ConvertFrom-Json
terraform state show aws_s3_bucket.validated
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c26-dev-validated
terraform plan
terraform destroy -auto-approve
terraform state list
```

有效默认值应通过四层检查；第二次 plan 为 `No changes`；销毁后 state 为空。删除运行产物：

```powershell
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate, .\terraform.tfstate.backup `
  -ErrorAction SilentlyContinue
Get-ChildItem -File -Filter '*.tfplan' | Remove-Item -Force
Get-ChildItem -Force | Select-Object Name
```

最终目录只能剩 `Readme.md` 和 `challenge-26.tf`。

## LocalStack 提醒

- LocalStack 固定账号通常为 `000000000000`；这里用它演示 check，不代表生产代码应写死账号。
- check 失败是 warning，适合持续健康断言；安全或合同硬约束应使用 validation/conditions。
- postcondition 依赖 provider 返回值，通常要到 refresh 或 apply 阶段才能完整求值。
