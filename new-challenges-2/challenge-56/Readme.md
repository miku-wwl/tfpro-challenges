# Challenge 56：HCP Terraform Run Workflow 场景判断

官方把 HCP Terraform 整个领域标为 **multiple-choice only**。本题不会要求 HCP 账户，也不会
把 LocalStack 冒充远端 worker；你先在本地运行一个小变更，再把同一变更放进 VCS、CLI/API、
speculative、saved-plan、run-task 和 run-trigger 场景中判断其生命周期。

## 官方考试目标

- **6a**：Analyze the HCP Terraform run workflow
- 本地辅助 **1b / 1c**：Generate and apply an execution plan

参考官方 [Run modes and options](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/run/modes-and-options)
与 [Run tasks](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/settings/run-tasks)。

## Starter 状态与诚实边界

~~~powershell
Set-Location .\new-challenges-2\challenge-56
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c56-local.tfplan'
terraform apply .\c56-local.tfplan
terraform output local_run_contract
~~~

这只在本机 Terraform + LocalStack 中创建 bucket。后续 HCP tasks 是配置审阅/口头判断，不
执行 `cloud` block、不需要 token，也不产生 HCP 资源。

## Task 1：画出本地 Run 的不可变证据

确认 saved plan 把配置、输入与 prior state snapshot 固定下来。把 `release` 改为 `v2`，
生成但不应用 `c56-v2.tfplan`，用 `terraform show` 记录唯一 tag update。

与结对 AI 给本地流程标出 `plan → human review → apply same plan → new state`，并说明直接
`terraform apply` 为什么会在确认前重新生成计划，而 apply saved plan 不会。

## Task 2：判断 Pull Request 的 Speculative Plan

场景：HCP workspace 已连接 VCS 主分支，开发者打开 PR 把 release 改为 v2。

逐项判断并解释：

1. PR 自动触发的是 standard run 还是 speculative/plan-only run；
2. 该 plan 能否被确认后 apply；
3. 它能否执行 policy checks；
4. 它是否成为 workspace current run 或阻塞普通 run queue。

正确模型是：PR 预览用于评审，不能 apply；它可以接受 policy 检查，但不是待发布的 current
run，plan-only 也不占用普通 run queue。

## Task 3：判断 Merge 后的 Standard Run

场景：PR 合并到 workspace 监听的分支，`auto-apply = false`。

按顺序写出 configuration fetch、plan、checks、confirmation、apply、state update。成功 plan
应等待有权限的人确认；把 auto-apply 改为 true 后，成功检查可自动进入 apply。Failed plan
或 mandatory policy failure 不能因 auto-apply 而越过门禁。

## Task 4：区分 HCP Saved Plan Run

Terraform 1.6 可通过 CLI workflow 创建 HCP saved plan run。判断：

- 它是否会因为 workspace 开启 auto-apply 而自动应用；
- 等待确认期间另一个 run 更新 state 后会怎样；
- 它的 plan/check 阶段是否必须等待普通 run queue。

期望结论：saved plan 不会 auto-apply；state 先变化会使它 stale 并被丢弃；其 planning/checks
可越过普通队列开始，但 apply 仍受状态连续性保护。

## Task 5：把 Run Task 与 Run Trigger 放到正确位置

设计一个安全扫描服务和一个下游 application workspace：

- Run task 把 run data 发给外部服务，由服务返回 pass/fail；enforcement 决定能否继续。
- Run trigger 表达 workspace 之间的运行依赖；上游成功 apply 后才应触发下游新 run。

解释为什么 run task 不是 child module、run trigger 也不是
`terraform_remote_state`。前者扩展运行门禁，后者启动另一个 workspace run；两者都不直接
替代 HCL 数据引用。

## Task 6：完成本地发布并清理

回到 LocalStack，把源码保持 v2，应用先前审阅的 `c56-v2.tfplan`，再确认 clean plan：

~~~powershell
terraform apply .\c56-v2.tfplan
terraform plan
terraform destroy -auto-approve
Remove-Item -Force .\c56-*.tfplan -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
~~~

恢复 release v1 starter，最终目录只剩两份源文件。

## 自检

能清楚回答“哪种 run 可 apply、谁触发、在哪个阶段阻断、何时 stale”才算完成。LocalStack
只帮助观察 Terraform plan/apply，不验证 HCP 队列、权限、policy 或远端 worker。
