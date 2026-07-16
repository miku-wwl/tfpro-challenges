# Challenge 93：All-Aliased Providers 与隐式空 Default

当一个 provider type 的所有显式 configurations 都带 alias 时，Terraform 会合成一个
空的 default configuration。未写 `provider = ...` 的 resource 或 data source 会绑定这个
空 default，而不是自动挑选某个 alias。本题从可运行基线出发，刻意进入这一错误，再用
provider graph 和 state 证据完成无替换修复。

## 考纲定位

- **5b**：Configure providers, including aliasing
- **5c**：Manage provider authentication
- **5d**：Troubleshoot provider errors
- 辅助使用 **1e**：检查 provider 重绑定前后的资源身份

## 开始前

```powershell
Set-Location .\new-challenges-4\challenge-93
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
```

Starter 只有一个完整 default provider 和一个 `aws.audit` alias。基线中的 AWS calls 都
明确指向本机 `http://localhost:4566`。请在新开的专用 PowerShell 终端完成本题，关闭
它即可丢弃 Task 2 的诊断环境变量。

## Task 1：部署 Default + Alias 基线

工作目录：`new-challenges-4/challenge-93`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
$before = terraform output -json routing_contract | ConvertFrom-Json
$before
terraform state list
```

预期结果：

- `aws_s3_bucket.primary` 创建 `tfpro-c93-primary`，使用 default provider。
- `aws_s3_bucket.audit` 创建 `tfpro-c93-audit`，使用 `aws.audit`。
- 两个 caller identities 都是 LocalStack account `000000000000`。

## Task 2：刻意制造 All-Aliased Provider 故障

编辑第一个 `provider "aws"` block，只添加：

```hcl
alias = "primary"
```

暂时不要修改 `data.aws_caller_identity.primary` 或 `aws_s3_bucket.primary`。现在两个显式
provider blocks 都带 alias，而这两个 consumers 仍请求 default provider。

空 default 没有源码中的 LocalStack endpoint。为了保证预期失败绝不会尝试真实 AWS，先在
当前专用终端覆盖为公开测试凭证、LocalStack endpoint 与一个故意无效的 Region：

```powershell
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "not-a-region"
$env:AWS_REGION = "not-a-region"
$env:AWS_ENDPOINT_URL = "http://localhost:4566"
$env:AWS_ENDPOINT_URL_S3 = "http://localhost:4566"
$env:AWS_ENDPOINT_URL_STS = "http://localhost:4566"
$env:AWS_EC2_METADATA_DISABLED = "true"
```

```powershell
terraform fmt -check
terraform validate
terraform providers
terraform plan
```

静态 validation 会通过，因为 schema 仍存在；plan 必须在配置 AWS provider 时失败，
实测错误同时说明 provider 需要显式配置且 `not-a-region` 无效。
关键诊断不是错误文本的逐字匹配，而是：未限定的 consumers 绑定了 Terraform 合成的空
default，而不是 `aws.primary`。故意无效的 Region 让失败发生在任何 API call 之前。

不要临时设置真实 AWS credentials，也不要删除 state。

## Task 3：给每个 Consumer 显式绑定 Alias

保持两个 provider blocks 都带 alias。做最小修复：

- `data.aws_caller_identity.primary` 添加 `provider = aws.primary`。
- `aws_s3_bucket.primary` 添加 `provider = aws.primary`。
- Audit data/resource 已有 `provider = aws.audit`，不要改变。

```powershell
terraform fmt
terraform validate
terraform plan '-out=alias-rebind.tfplan'
terraform show alias-rebind.tfplan
```

预期不出现 create、delete 或 replace。应用已审阅的计划：

```powershell
terraform apply alias-rebind.tfplan
$after = terraform output -json routing_contract | ConvertFrom-Json
$before.primary.bucket -eq $after.primary.bucket
$before.audit.bucket -eq $after.audit.bucket
```

两行都必须是 `True`。

## Task 4：从 State 证明两个 Alias 都被使用

```powershell
terraform providers
$state = terraform state pull | ConvertFrom-Json
$state.resources | Select-Object type, name, provider
terraform state show aws_s3_bucket.primary
terraform state show aws_s3_bucket.audit
terraform output routing_contract
terraform plan -detailed-exitcode
```

最终要求：

- 配置没有显式 default AWS provider。
- 所有 AWS resources 与 data sources 都有静态 provider 选择。
- State 中同时出现 `.primary` 与 `.audit` provider addresses。
- 两个物理 bucket ID 不变，最后 plan 退出码为 `0`。

## 清理

```powershell
terraform destroy -auto-approve
Remove-Item -Force .\alias-rebind.tfplan -ErrorAction SilentlyContinue
Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:AWS_DEFAULT_REGION -ErrorAction SilentlyContinue
Remove-Item Env:AWS_REGION -ErrorAction SilentlyContinue
Remove-Item Env:AWS_ENDPOINT_URL -ErrorAction SilentlyContinue
Remove-Item Env:AWS_ENDPOINT_URL_S3 -ErrorAction SilentlyContinue
Remove-Item Env:AWS_ENDPOINT_URL_STS -ErrorAction SilentlyContinue
Remove-Item Env:AWS_EC2_METADATA_DISABLED -ErrorAction SilentlyContinue
```

确认 `tfpro-c93-primary` 与 `tfpro-c93-audit` 均已删除。

## Terraform 1.6 边界

本题只使用 Terraform 1.6 的 provider alias 与 resource/data `provider` meta-argument。
不要通过环境中的真实 AWS profile“修复”空 default，也不要使用动态 provider references、
mock provider、ephemeral values 或 write-only arguments。
