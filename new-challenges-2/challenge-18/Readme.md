# Challenge 18：Target 的依赖闭包与最小 `depends_on`

Starter 声明 artifact bucket、其中的 release object，以及一个独立 audit bucket。Release
object 通过属性引用自然依赖 artifact bucket，却还没有表达“发布前 audit bucket 必须存在”
这条业务边。你会用两次 targeted plan 对比隐式与显式依赖闭包。

## 官方考试目标

- **1b**：生成并审阅包含 `-target` 的执行计划
- **1c**：受控应用 saved plan，并回到完整 workflow
- **2d**：使用 `depends_on` meta-argument 并分析依赖图

Target 只用于本题的依赖图诊断与分阶段练习，不是日常部署默认方式。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-18
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
Invoke-RestMethod http://localhost:4566/_localstack/health
```

目录只有两个源文件，没有 state。Starter 中三个 managed resources 都合法：

- `aws_s3_bucket.artifacts`：`tfpro-c18-artifacts`；
- `aws_s3_object.release`：`releases/current.txt`；
- `aws_s3_bucket.audit`：`tfpro-c18-audit`。

## Task 1：先建立完整计划基准

```powershell
terraform init -input=false
terraform fmt -check
terraform validate
terraform graph |
  Select-String -Pattern 'aws_s3_bucket.artifacts|aws_s3_object.release|aws_s3_bucket.audit'
terraform plan -input=false
```

完整 plan 应有 **3 to add**。图中 object 因 `bucket = aws_s3_bucket.artifacts.id` 自动获得
到 artifact bucket 的隐式依赖；audit bucket 此时没有连到 release object。

## Task 2：只 Target Release Object，观察隐式闭包

```powershell
terraform plan -input=false `
  '-target=aws_s3_object.release' `
  '-out=implicit-closure.tfplan'
terraform show implicit-closure.tfplan
```

Saved plan 应只创建 artifact bucket 与 release object，共 **2 to add**。即使 target 只写了
object，Terraform 仍包含其上游 bucket；独立的 audit bucket 不在闭包中。Target 警告是
预期的。不要 apply 这份缺少业务依赖的计划。

## Task 3：从 Plan JSON 证明闭包边界

```powershell
$implicitPlan = terraform show -json implicit-closure.tfplan | ConvertFrom-Json
$creates = $implicitPlan.resource_changes |
  Where-Object { $_.change.actions -contains 'create' }
$creates.address
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c18-artifacts
$LASTEXITCODE
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c18-audit
$LASTEXITCODE
```

地址列表只能是 artifact bucket 与 release object，不能出现 audit。两个 API 查询都应返回
非零，因为 saved plan 只描述动作，尚未 apply，也没有 state 写入。

## Task 4：添加唯一的业务依赖并重算 Target 闭包

在 `aws_s3_object.release` 中添加一个 `depends_on` meta-argument，只引用
`aws_s3_bucket.audit`。不要重复声明 artifact bucket 的依赖，因为属性引用已经建立那条边。

```powershell
terraform fmt
terraform validate
terraform graph |
  Select-String -Pattern 'aws_s3_bucket.artifacts|aws_s3_object.release|aws_s3_bucket.audit'
terraform plan -input=false `
  '-target=aws_s3_object.release' `
  '-out=explicit-closure.tfplan'
terraform show explicit-closure.tfplan
```

三者此时都尚未创建，所以新计划必须是 **3 to add**：artifact 与 audit 两个上游 bucket，
加上 release object。Audit 现在因为显式边进入 object 的上游闭包。确认后应用同一份计划：

```powershell
terraform apply -input=false explicit-closure.tfplan
terraform state list
```

## Task 5：回到完整 Plan 并从 S3 API 验收

```powershell
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
terraform output -json dependency_contract
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c18-artifacts
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c18-audit
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c18-artifacts `
  --key releases/current.txt
```

完整 plan 退出码必须为 `0`；两个 bucket 和 object API 都成功。最终配置只能新增那一条
业务 `depends_on`，不能用一串 target 命令替代完整收敛检查。

## Task 6：按反向依赖顺序销毁并恢复 Starter

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c18-artifacts
$LASTEXITCODE
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c18-audit
$LASTEXITCODE
```

State 应为空，两个 API 检查都应非零。销毁时 object 会先于它依赖的两个 bucket 删除。
最后恢复源码并清除运行产物：

```powershell
git restore --source=HEAD -- .\challenge-18.tf
Remove-Item -LiteralPath .\.terraform -Recurse -Force
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,`
  .\terraform.tfstate.backup,.\implicit-closure.tfplan,`
  .\explicit-closure.tfplan -Force -ErrorAction SilentlyContinue
git diff --exit-code -- .\challenge-18.tf
Get-ChildItem -Force | Select-Object -ExpandProperty Name
```

最终只保留 `Readme.md` 和恢复到无显式依赖的 `challenge-18.tf`。

## Terraform 1.6 与 LocalStack 边界

- 本题只使用 Terraform 1.6 已有的 resource targeting、saved plan、隐式图边与
  `depends_on`。
- `depends_on` 应表达 provider 看不见的行为依赖；能用值引用表达的数据依赖继续使用引用。
- Target 可能忽略配置中其他变更，apply 后必须运行不带 target 的完整 plan。
- LocalStack S3 模拟对象足以验证图和 state；不把模拟环境的时序当成真实 AWS 发布保证。
