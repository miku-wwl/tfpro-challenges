# Challenge 58：HCP Terraform 的 AWS Dynamic Provider Credentials

静态 workspace access keys 即使被标为 sensitive，仍需要长期存储和轮换。HCP Terraform 可以
为每次 plan/apply 生成 OIDC workload identity token，让 AWS 验证 claims 后签发短期凭证。
本题先用环境变量连接 LocalStack，再审阅真实 HCP→AWS 信任链；LocalStack 不模拟 HCP OIDC。

## 官方考试目标

- **6c**：Manage provider credentials in HCP Terraform
- 辅助 **5c**：Understand provider authentication boundaries

领域 6 官方只出选择题。事实依据：
[AWS dynamic credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration)。

## Starter 状态

Provider block 刻意没有 key：

~~~powershell
Set-Location .\new-challenges-2\challenge-58
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output local_identity_contract
~~~

这只证明 AWS provider 能从本机 environment credential chain 取得 LocalStack 假凭证；它
没有启用 HCP dynamic credentials。

## Task 1：按顺序解释 OIDC 交换

把以下七步排序并说明谁负责：

1. HCP 为 plan 或 apply 生成带 run metadata 的 OIDC token；
2. HCP 把 token 交给 AWS；
3. AWS 用 HCP 的公开 signing key 验证 token；
4. AWS trust policy 检查 issuer、`aud` 与 `sub`；
5. AWS 返回临时凭证；
6. HCP 把临时凭证提供给该阶段的 provider；
7. run environment 结束并丢弃凭证。

核心区别：HCP 不把一对永久 AWS keys“动态轮换”；AWS 根据受信 workload identity 临时签发。

## Task 2：审阅最小 Trust Claims

为 `prod-network` workspace 设计 trust condition。`sub` 至少约束：

- organization；
- project；
- workspace；
- `run_phase`（`plan` 或 `apply`）。

`aud` 默认应为 `aws.workload.identity`，除非 workspace 显式配置了其他 audience。不能只信任
issuer 而允许任意 HCP organization/workspace assume role。Plan/apply 权限不同时，应使用
两套 role/trust conditions，而不是给 plan 与 apply 同一组写权限。

## Task 3：选择正确的 Workspace Environment Variables

单 role 模式需要判断：

- `TFC_AWS_PROVIDER_AUTH = true`；
- `TFC_AWS_RUN_ROLE_ARN` 指向 AWS role；
- provider Region 仍必须由 provider block 或 `AWS_REGION` 提供。

双 role 模式改用 `TFC_AWS_PLAN_ROLE_ARN` 与 `TFC_AWS_APPLY_ROLE_ARN`。这些是 HCP workspace
的 **environment variables**，不是普通 Terraform input variables。Role ARN 不是 secret key，
但仍应由受控 workspace/variable set 管理。

## Task 4：排除会干扰 Dynamic Auth 的配置

审阅 starter provider。若把它用于真实 HCP workspace，需要移除 LocalStack endpoints 与三项
LocalStack skip flags，同时保持不写 `access_key`、`secret_key`、静态 profile 或冲突的
credential file。Dynamic credentials 只负责认证，不会自动选择 Region 或把 endpoint 改成 AWS。

说明为什么把永久 `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` 也留在 workspace 会制造
模糊的 credential precedence 和安全债务。

## Task 5：处理 Plan/Apply 与 Query 的最小权限

为场景分配：

- plan role：允许读取与生成准确计划所需操作；
- apply role：允许被批准变更所需写操作；
- query run：使用 plan credential configuration。

不要假定 plan 永远只需纯 read 权限；某些 provider planning/data-source 行为需要额外 API。
应从实际 provider 调用与失败证据收敛权限，同时保持 plan/apply 分离。

若一个 workspace 使用多个 AWS aliases，说明 HCP 需要为各配置提供 tagged credential set，
Terraform 配置也要接收 HCP 注入的 shared-config paths；不能靠一个 role ARN 动态猜 alias。

## Task 6：清理本地证据

~~~powershell
terraform plan
terraform destroy -auto-approve
Remove-Item Env:AWS_ACCESS_KEY_ID
Remove-Item Env:AWS_SECRET_ACCESS_KEY
Remove-Item Env:AWS_DEFAULT_REGION -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
~~~

最终只保留两份源文件。本地 state/API 应为空；没有 HCP token、OIDC provider 或真实 AWS role
需要清理，因为本题从未创建它们。

## 自检

能区分“workspace 静态 variables”“HCP OIDC token”“AWS 临时 credentials”“provider
configuration”四层，并能指出 plan/apply role 的 trust claim 边界，才算完成 6c 场景。
