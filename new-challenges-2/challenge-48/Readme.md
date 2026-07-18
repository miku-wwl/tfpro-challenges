# Challenge 48：从 Source Credentials 到 AssumeRole Session 的认证链

Provider authentication 不是把 access key 写进 HCL。本题先用 starter 中明确可见的 LocalStack
假凭证建立 IAM role，再依次改为环境变量、临时 shared profile 与 `assume_role` alias，并
通过 caller/session data sources 证明“来源身份”和“委派身份”不是同一层。

## 官方考试目标

- **5b**：Configure providers, including aliasing, versioning, sourcing, and managing upgrades
- **5c**：Manage provider authentication
- **5d**：Troubleshoot provider errors

官方范围：[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。
所有凭证仅针对 `localhost:4566`；不要在本题写入真实 AWS key。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-48
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
terraform init
terraform apply -auto-approve
terraform output source_identity
~~~

Starter 用 provider block 中的 `test/test` 创建 `tfpro-c48-deployment` role。先记录 source
ARN 与 role ARN；当前还没有 delegated provider。

## Task 1：把凭证从 HCL 移到环境

删除 provider block 中的 `access_key` 与 `secret_key`，保留 Region、LocalStack endpoints
与三项 skip flags。环境变量已在上方设置。

~~~powershell
terraform fmt
terraform validate
terraform plan
~~~

预期 `No changes`。临时清除两个 AWS key 环境变量再 plan，应在 provider 初始化或认证阶段
失败；恢复为 `test` 后继续。静态 validation 通过不代表运行期一定能取得凭证。

## Task 2：创建仅供本题使用的 Shared Profile

在本题目录临时创建 `.aws/credentials` 与 `.aws/config`，只含一个 `c48-source` profile：

~~~powershell
New-Item -ItemType Directory -Force .\.aws | Out-Null
@'
[c48-source]
aws_access_key_id = test
aws_secret_access_key = test
'@ | Set-Content -Encoding ascii .\.aws\credentials
@'
[profile c48-source]
region = us-east-1
'@ | Set-Content -Encoding ascii .\.aws\config
~~~

修改默认 provider：设置 `profile = "c48-source"`，并用
`shared_credentials_files`/`shared_config_files` 指向这两个文件。清除 AWS key 环境变量后
再次 plan，仍应无变更。不要把这两个临时文件提交。

## Task 3：添加 Delegated Provider Alias

添加 `aws.delegated`，要求：

- 仍从 `c48-source` profile 取得 source credentials；
- `assume_role.role_arn` 引用 `aws_iam_role.deployment.arn`；
- session name 为 `tfpro-c48-session`；
- IAM/STS endpoints 与 skip flags 完整；
- 不在 alias 中复制 role ARN 字符串。

然后添加走该 alias 的 `data.aws_caller_identity.delegated`。

~~~powershell
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve
~~~

第一次 plan 可能同时刷新 source identity、读取 role 并调用 LocalStack STS，但不应重建 role。

## Task 4：用 Session Context 验证委派身份

添加 `data.aws_iam_session_context.delegated`，其 `arn` 来自 delegated caller identity，并
显式使用 `aws.delegated`。发布 `authentication_contract`，至少包含 source ARN、delegated
ARN、issuer ARN、issuer name 与 role ARN。

~~~powershell
terraform output authentication_contract
terraform state list
aws --endpoint-url=http://localhost:4566 sts get-caller-identity --profile c48-source
~~~

CLI 的 source profile 不会自动 assume role，因此 CLI ARN 应与 source 层一致；Terraform
delegated ARN 应体现 assumed-role session。不要只比较 account ID。

## Task 5：复现一个最小认证故障再修复

临时把 alias 的 role ARN 改成不存在的 `tfpro-c48-missing`，运行 plan 并记录错误发生在
credential discovery、STS AssumeRole 还是资源读取阶段。不要应用。恢复引用表达式后：

~~~powershell
terraform plan
~~~

最终必须为 `No changes`。错误分类比背诵完整报错文本更重要。

## Task 6：按依赖顺序清理

~~~powershell
terraform destroy -auto-approve
Remove-Item -Recurse -Force .\.aws
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Get-ChildItem -Force
~~~

销毁必须在删除 profile 前执行，否则 provider 无法再认证。把 `challenge-48.tf` 恢复 starter，
最终目录只保留两份源文件。

## LocalStack 与真实认证的边界

`test/test` 和 LocalStack STS 只用于练习 credential chain、provider alias 与 session identity。
真实 AWS 还会执行更严格的信任策略、权限和令牌校验；HCP dynamic credentials 在 Challenge 58
单独以官方选择题范围练习，不能由这里的静态 profile 代替。
