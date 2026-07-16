# Challenge 80：LocalStack AssumeRole 委派与身份核验

这个实验模拟生产中常见的 provider authentication chain：默认 AWS provider 从
运行环境取得 source credentials，先创建一个 deployer role；随后 aliased provider
通过 STS AssumeRole 管理 S3 bucket。最终要用 caller/session data sources 证明请求
确实经过委派，而不是继续使用 bootstrap identity。

## 考纲定位

- **5c** Manage provider authentication
- **5d** Troubleshoot provider errors
- **5b** Configure provider aliases
- **2b** Query providers with `aws_caller_identity` and
  `aws_iam_session_context`

这里只使用值为 `test` 的 LocalStack mock credentials。不要把真实 AWS access key
写入 `.tf`、state、命令历史或本题目录。

## 起始状态

`challenge-80.tf` 已提供默认 provider、role trust policy、最小 S3 policy 和
attachment。它**尚未**包含 delegated provider 或 bucket。这是必要的两阶段起点：
一个尚不存在的 role 不能在同一次初始 provider 配置中被 Assume。

## 任务

### Task 1：只用环境变量提供 LocalStack source credentials

打开 PowerShell，进入 `new-challenges-3/challenge-80`，只为当前终端设置：

```powershell
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
terraform init
terraform validate
terraform plan
```

请使用专门用于本实验的新 PowerShell 终端；Terraform 必须是 1.6.x。关闭该终端
即可回到原有凭证环境，不要在正在使用真实 AWS credentials 的会话中覆盖变量。

provider 中已经锁定 IAM/S3/STS endpoints 为 `http://localhost:4566`，因此这些
mock credentials 不会发送到真实 AWS。plan 应准备 role、policy、attachment；
`bootstrap_identity.account_id` 应为 `000000000000`。

### Task 2：先建立可被 Assume 的 role

本题把 targeted apply 用作 bootstrap/恢复手段，不是日常发布流程。只创建 role：

```powershell
terraform apply '-target=aws_iam_role.deployer'
terraform state show aws_iam_role.deployer
```

确认 ARN 精确为：

```text
arn:aws:iam::000000000000:role/TfProChallenge80Deployer
```

如果 role 不存在就提前添加 delegated provider，provider 初始化会先调用 STS，
导致 plan 在任何 resource action 之前失败。

### Task 3：添加 delegated provider alias

修改 `challenge-80.tf`，新增第二个 AWS provider configuration：

- alias 为 `delegated`；Region 为 `us-east-1`。
- 保留与默认 provider 相同的 LocalStack endpoints、S3 path style 和安全
  `skip_*` 参数。
- 不写 `access_key` / `secret_key`，继续从 Task 1 的环境变量获取 source
  credentials。
- 添加 `assume_role`，role ARN 使用已经给出的固定
  `local.role_arn`，session name 使用 `tfpro-challenge80`。

Provider configuration 必须在 plan 前就可求值，因此不能把
`aws_iam_role.deployer.arn` 直接放进 `assume_role`。

```powershell
terraform fmt
terraform validate
terraform plan
```

计划会继续显示待补齐的 policy 和 attachment。此时 alias 还没有 consumer，Terraform
可能裁剪这份未使用的 provider configuration；因此本步只验收语法，不能据此声称
STS AssumeRole 已成功。真正的运行期身份验证发生在 Task 4。

### Task 4：让委派身份管理 bucket

在 `challenge-80.tf` 新增：

1. `aws_s3_bucket.delegated`，bucket name 使用 `local.bucket_name`，
   `force_destroy = true`，显式 `provider = aws.delegated`。
2. bucket 对 `aws_iam_role_policy_attachment.deployer` 添加必要的显式
   `depends_on`，表达“权限就绪后才发布资源”，同时保证 destroy 反向顺序。
3. `aws_caller_identity.delegated` data source，绑定相同 alias。

运行 plan。这是 `aws.delegated` 第一次被 resource/data source 使用，STS AssumeRole
必须在此时成功。预期默认 provider 管理 IAM 三个 resources，delegated provider
管理 bucket 和 delegated caller query。

### Task 5：核验 session issuer，不只看 account ID

LocalStack 中 bootstrap 和 delegated identities 都属于账号 `000000000000`，仅比较
account ID 不能证明 AssumeRole。新增 `aws_iam_session_context.delegated` data
source：

- `arn` 使用 delegated caller identity 的 ARN；
- 显式绑定 `aws.delegated`；
- 新增一个 sensitive=false 的 `authentication_contract` output，只包含
  bootstrap ARN、delegated caller ARN、session issuer ARN、bucket name。

```powershell
terraform apply -auto-approve
terraform output authentication_contract
```

预期：

- delegated caller ARN 包含
  `assumed-role/TfProChallenge80Deployer/tfpro-challenge80`；
- session issuer ARN 等于 `local.role_arn`；
- output/state 中没有 access key 或 secret key 值。

本题已在 LocalStack Community 4.14.0 验证 session issuer 回读。如果更旧版本不支持该
data source，应升级到 4.14.0 再完成本 Task，不能跳过 issuer 验收后声称整题完成。

### Task 6：从 state 验证两个 provider configurations

```powershell
terraform state list
terraform state pull | Select-String -Pattern 'provider.*\.delegated'
terraform plan
```

role/policy/attachment 应使用默认 provider；bucket 应引用 `aws.delegated`。最终 plan
应为 `No changes`。

## 最终验收

- source credentials 只来自当前终端环境，`.tf` 中没有 secret。
- role 先建立，delegated provider 再 AssumeRole。
- IAM resources 使用默认 provider，S3 bucket 使用 `aws.delegated`。
- caller ARN 能证明 assumed-role session；LocalStack 支持时 issuer 精确等于 role ARN。
- 最终 plan 为 `No changes`，state/output 不包含 credentials。

## 清理

仍在 `challenge-80` 目录执行：

```powershell
terraform destroy -auto-approve
Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:AWS_DEFAULT_REGION -ErrorAction SilentlyContinue
```

清理图应先删除 delegated bucket，再解除 attachment/删除 IAM policy 和 role。
参考：[AWS provider authentication](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration)、[Provider configuration](https://developer.hashicorp.com/terraform/language/providers/configuration)。
