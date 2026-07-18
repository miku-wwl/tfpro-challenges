# Challenge 57：HCP Workspaces、Execution Mode 与最小权限场景

HCP Terraform workspace 是一个保存 configuration、variables、state、run history 和访问控制的
远端管理对象；它不是 `terraform workspace new` 创建的 CLI state namespace。本题用一个
LocalStack workload 作为讨论对象，逐步为 dev/prod 设计 workspace 边界、execution mode、
变量来源、team permissions 与 remote-state consumers。

## 官方考试目标

- **6b**：Understand HCP Terraform workspaces and their configuration options, including access management

官方明确说明领域 6 只出选择题。本题不连接 HCP；参考
[HCP Terraform workspaces](https://developer.hashicorp.com/terraform/cloud-docs/workspaces) 与
[Workspace permissions](https://developer.hashicorp.com/terraform/cloud-docs/users-teams-organizations/permissions/workspace)。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-57
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output local_workspace_contract
~~~

本地配置和 state 都在当前 working directory。先列出：配置来自两个源文件，变量来自 default，
state 在本地，credentials 在 provider block，run history 只有终端输出。

## Task 1：把同一清单映射到 HCP Workspace 内容

假设创建 `network-dev` 与 `network-prod` 两个 HCP workspaces。为每个 workspace 指出：

- configuration 来自哪个 VCS repo/working directory 或 CLI/API upload；
- `environment`、`owner` 应作为 Terraform variables 还是 environment variables；
- state 和历史 state versions 存放在哪里；
- run logs、comments 与触发来源在哪里审计。

HCP workspace 像一个独立 working directory 管理一组基础设施；dev/prod 不应靠一个 HCP
workspace 内的 CLI workspace 偷偷复用 state。

## Task 2：选择 Remote、Local 或 Agent Execution

对三种场景选择 execution mode 并解释：

1. 公网可达 providers，期望 HCP 托管 disposable workers；
2. 团队只想把 state 存 HCP，Terraform 命令仍从工程师机器运行；
3. provider endpoint 只在私网可达，需要组织自管 worker。

期望分别考虑 remote、local、agent。Local execution 关闭远端执行，且 HCP workspace
variables/variable sets 不会像 remote run 那样自动注入；agent mode 需要可访问私网的 agent
pool。改变已有待 apply run 的 execution mode 会使其失去一致的执行环境。

## Task 3：给 Variables 正确分类

把下列值分到 Terraform variable、environment variable、sensitive 标记和 variable set：

- `environment = "prod"`；
- AWS 认证开关/role ARN；
- `TF_LOG`；
- 多个 workspaces 共享的 provider 配置；
- 只属于单 workspace 的业务 owner。

Terraform variables 对应配置输入；environment variables 配置 shell/provider/CLI。Variable set
可复用到多个 workspaces/projects。Sensitive 值是 write-only/受保护显示，不代表它不会进入
Terraform state。

## Task 4：按职责设计 Team Access

场景中有 viewer、release engineer、security admin：

- viewer 只需查看 run 结果；
- release engineer 需要排队/确认 runs，但不应直接改敏感变量或 state；
- security admin 管理 policy overrides，不负责日常 apply。

为每类人选择最小 workspace/project/team permissions。特别说明 state read 可能暴露完整
state 中的敏感数据；state write 还允许上传 state versions 和执行 state/import 类维护命令，
不应因“只想看 output”就授予。

## Task 5：限制 Remote State Consumers

Producer workspace 发布 network outputs，只有两个 application workspaces 需要消费。选择
“specific workspaces”而不是 organization-wide/global access，并列出消费者。解释：

- 允许 state sharing 不等于授予对 producer 的 apply 权限；
- `terraform_remote_state` 读取者通常接触完整 state snapshot，不能只靠 output 看似无敏感值；
- 更小的显式 output 合同仍需最小化 producer state 中的秘密。

新 workspace 默认不应假定全组织都可读取 state。

## Task 6：回到本地核对概念差异并清理

~~~powershell
terraform workspace list
terraform state list
terraform plan
terraform destroy -auto-approve
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
~~~

本地 `terraform workspace list` 只显示 CLI namespaces，无法显示假设中的 HCP teams、variables
或 run history。最终恢复两文件 starter。

## 自检

完成时应能针对任意场景回答四件事：基础设施集合边界、执行位置、输入来源、谁能读/改
configuration、variables、state 与 runs。LocalStack 没有验证 HCP RBAC，这部分按官方选择题
范围进行配置审阅。
