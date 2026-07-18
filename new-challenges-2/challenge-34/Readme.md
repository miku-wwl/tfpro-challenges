# Challenge 34：审计 Sensitive 值、State 与 Saved Plan

这个练习不会创建真实 secret manager。你会先运行一个不接触 secret 的安全基线，再有意
把临时 token 放入 `terraform_data`，观察 CLI 的脱敏与文件落盘并不是同一件事，最后
改为只发布 hash 的合同。Vault 只作为架构讨论，不是本题依赖。

## 官方考试目标

- **2f**：Analyze best practices for managing sensitive data, such as using Vault for secrets management
- **2e**：Configure input variables and outputs, including complex types
- **3c**：Use the Terraform workflow in automation

使用 Terraform 核心 `terraform_data` 与官方 AWS caller identity data source。兼容
Terraform `>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-34
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 声明了 nullable、sensitive 的 `release_token`，默认是 `null`。现有
`terraform_data.baseline` 与输出只保存 challenge/account metadata，不引用 token，
因此第一次 apply 不会把 secret 写入 state。

## Task 1：确认安全基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output starter_audit
terraform state pull |
  Select-String -SimpleMatch 'release_token'
```

输出应显示 LocalStack account，搜索不应找到 token 字段。

## Task 2：有意创建一个不安全实验

只为本 task 设置一个高熵临时值：

```powershell
$env:TF_VAR_release_token = "tfpro-c34-Temp-7F9C2A61-DoNotReuse"
```

添加临时 `terraform_data.unsafe`，让它的 input 保存原始 token；再添加一个直接输出该
值且标记 sensitive 的临时 output。不要把 token 字面量写进 TF。

```powershell
terraform fmt
terraform validate
terraform plan '-out=unsafe.tfplan'
terraform show unsafe.tfplan
terraform apply unsafe.tfplan
```

人类可读 plan/output 应显示 `(sensitive value)`，但下面两项应能找到原文：

```powershell
terraform state pull |
  Select-String -SimpleMatch $env:TF_VAR_release_token
terraform show -json .\unsafe.tfplan |
  Select-String -SimpleMatch $env:TF_VAR_release_token
```

这证明 `sensitive = true` 负责界面脱敏，不会加密 state 或 saved plan。

## Task 3：审计传播与 Nonsensitive 边界

在 console 中比较原值、`sha256(...)` 和显式 `nonsensitive(...)` 的敏感传播：

```powershell
terraform console
```

不要对原始 token 调用 `nonsensitive`。只有经过单向 hash、且你明确接受离线猜测风险的
摘要才可作为非敏感合同字段。退出 console。

## Task 4：重构为 Hash-only 合同

删除临时 raw-token resource/output。创建 hash-only 审计对象，state 中只能保存：

- token 是否提供；
- SHA-256 摘要；
- caller account ID；
- 固定 contract version。

不得保存原文或可逆编码。输出命名为 `secret_audit_contract`。

```powershell
terraform plan '-out=hash-only.tfplan'
terraform show hash-only.tfplan
terraform apply hash-only.tfplan
terraform output secret_audit_contract
terraform show -json |
  Select-String -SimpleMatch $env:TF_VAR_release_token
```

当前 state JSON 不应再包含原文。旧 `unsafe.tfplan` 和 `terraform.tfstate.backup` 仍可能
包含它，这是预期的审计发现，不要误报为 Terraform 自动擦除历史文件。

## Task 5：讨论 Vault，但不把它变成依赖

和结对 AI 说明生产设计会如何从 Vault 或云 secret manager 在运行时取得 secret、限制
访问、轮换并审计。还要指出：只要某个 Terraform resource argument 需要原始 secret，
provider 仍可能把它存入 state；外部 secret manager 并不会自动解决 state 暴露。

本题不要安装 Vault provider、不要启动 Vault、也不要添加额外文件。

## Task 6：验证摘要、清理所有敏感产物

```powershell
$contract = terraform output -json secret_audit_contract | ConvertFrom-Json
$contract.token_sha256
aws --endpoint-url=http://localhost:4566 sts get-caller-identity
terraform state list
terraform plan
terraform destroy -auto-approve

Remove-Item -LiteralPath .\unsafe.tfplan -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\hash-only.tfplan -ErrorAction SilentlyContinue
Remove-Item -Path .\terraform.tfstate* -Force -ErrorAction SilentlyContinue
Remove-Item Env:\TF_VAR_release_token
```

合同不能含原始 token，account ID 应与 STS API 一致，稳定配置的 plan 应为
`No changes`。最后删除 `.terraform` 与 lockfile，确认目录只剩 `Readme.md` 和
`challenge-34.tf`。

## LocalStack 提醒

- LocalStack 的 `test/test` 不是生产 secret，本题临时 token 仍按敏感数据流程处理。
- Terraform local state 和 saved plan 都是明文容器，应由文件权限、加密存储和访问控制保护。
- Hash 对低熵 secret 可能被字典攻击；生产环境优先避免让 Terraform 接触原文。
