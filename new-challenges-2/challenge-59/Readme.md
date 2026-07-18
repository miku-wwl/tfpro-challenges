# Challenge 59：Policy as Code、Enforcement 与 Override 场景

Starter 的 prod bucket 故意缺少 `Owner` tag。本地 Terraform 认为配置完全有效；在 HCP
Terraform 中，Sentinel 或 OPA policy set 可以审查成功 plan 并根据 enforcement level 警告、
阻断或允许有权限的人 override。本题不安装 policy engine，而是用真实 plan JSON作为审阅对象。

## 官方考试目标

- **6d**：Analyze policy as code and governance features

官方明确把领域 6 作为选择题。参考
[Policy enforcement](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/policy-enforcement) 与
[Policy results](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/policy-enforcement/view-results)。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-59
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c59-violating.tfplan'
terraform show -json .\c59-violating.tfplan |
  Set-Content -Encoding utf8 .\c59-violating.json
~~~

不要 apply。确认 plan JSON 中 resource change 的 after.tags 含 Environment/Challenge，却没有
Owner。Local plan 成功只证明 Terraform 语言/provider schema 合法，不代表组织政策合规。

## Task 1：为 Plan 选择 Policy Framework

对同一个规则分别描述：

- Sentinel policy 使用 Sentinel language/imports 审查 plan、configuration、state 等数据；
- OPA policy 使用 Rego，HCP 把 run/plan JSON 作为 input，query 通常返回 deny 结果；
- policy set 把同一 framework 的 policies 组合，并连接到 organization、projects 或 workspaces。

Sentinel 与 OPA policy sets 可以同时关联同一 workspace，但单个 policy set 不能混放两种语言。
Policy code 宜放 VCS，获得评审、版本与审计记录。

## Task 2：判断 Enforcement Level

针对“prod 必须有 Owner”逐项判断：

| Framework / level | 失败后的预期 |
|---|---|
| Sentinel advisory | 显示警告，run 可继续 |
| Sentinel soft-mandatory policy check | 停止；有 override 权限时可继续 |
| Sentinel hard-mandatory policy check | 停止，不能 override |
| OPA advisory | 显示警告，run 可继续 |
| OPA mandatory | 停止；当前 HCP workflow 中需 override 权限才可继续 |

不要把“某人可以 apply”误解为“他一定有 policy override 权限”。Override 是单独治理能力，
而且不会永久修改 policy；后续 runs 仍会重新评估。

## Task 3：把 Policy 放在正确 Scope

场景要求所有 prod projects 强制 Owner，sandbox 只告警。设计：

- 一个关联 prod projects/tags 的 mandatory policy set；
- 一个只关联 sandbox 的 advisory set，或明确排除规则；
- 管理 policy set 的权限与日常 workspace apply 权限分离。

解释 global policy set、project/workspace association 和 exclusion 的 blast radius。不要为了
修复一个 workspace 就直接把 organization-wide policy 关掉。

## Task 4：修复配置而不是依赖 Override

给 bucket tags 添加非空 `Owner = "platform"`，重新生成 plan JSON：

~~~powershell
terraform fmt
terraform plan '-out=c59-compliant.tfplan'
terraform show -json .\c59-compliant.tfplan |
  Set-Content -Encoding utf8 .\c59-compliant.json
Select-String -Path .\c59-compliant.json -Pattern '"Owner"'
~~~

现在相同 policy 应通过。Apply 同一计划并核验 LocalStack：

~~~powershell
terraform apply .\c59-compliant.tfplan
terraform output governance_contract
terraform plan
~~~

正常修复留下可重复的代码意图；override 只用于经过授权的例外，不是永久解决方案。

## Task 5：区分 Policy、Run Task 与 HCL Condition

为三种要求选择最合适层次：

1. 单 module 输入的端口范围；
2. 全组织 prod resources 必须带 Owner；
3. 把 plan 交给外部漏洞扫描服务。

分别优先考虑 variable validation/precondition、policy as code、run task。它们可以组合：
HCL condition 靠近配置作者，policy 统一治理 plan，run task 集成外部系统。任何一个都不是
另外两个的同义词。

同时记住 policy 通常只对成功 plan 评估；HCL/provider plan 已失败时，没有合格 plan 供后续
政策判断。

## Task 6：本地清理与范围声明

~~~powershell
terraform destroy -auto-approve
Remove-Item -Force .\c59-*.tfplan, .\c59-*.json -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
~~~

恢复缺少 Owner 的 starter，最终只保留两份源文件。没有 HCP policy set 需要删除，因为本题
没有连接 HCP；本地成功 apply 也不构成 policy engine 的端到端验证。

## 自检

完成时应能看到一个 policy failure 场景后回答：policy 作用范围、framework、enforcement、
谁能 override、修复后何时重新评估，以及它和 run task/HCL condition 的区别。
