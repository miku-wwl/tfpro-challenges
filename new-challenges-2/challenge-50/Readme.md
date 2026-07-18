# Challenge 50：Provider 约束、Lockfile 与一次可回退的 Upgrade

版本约束表达“允许选择什么”，lockfile 记录“团队这次选择了什么”。本题先以 AWS
`5.80.0` 部署稳定 bucket，再在隔离副本复现无解约束，最后在原 state 上执行受控的
`5.x` upgrade，并证明 provider 选择变化不等于远端资源必须变化。

## 官方考试目标

- **3a**：Manage Terraform, providers, and modules using version constraints
- **5b**：Configure providers, including aliasing, versioning, sourcing, and managing upgrades
- **5d**：Troubleshoot provider errors

AWS provider 版本不是考试固定要求；`5.80.0` 是本仓与 LocalStack 已验证的起点。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-50
terraform init
terraform providers
Get-Content .\.terraform.lock.hcl
terraform apply -auto-approve
terraform output release_contract
~~~

记录 lockfile 中 selected version、constraints 与 hashes。部署后 state 只有一个 bucket。

## Task 1：证明普通 Init 优先沿用 Lockfile

不改配置，重复：

~~~powershell
terraform init
terraform providers
terraform plan
~~~

预期仍选择 `5.80.0` 且 plan 为 `No changes`。普通 init 不会仅因 registry 出现了更新版本
就擅自升级已锁定的 selection。

## Task 2：在隔离副本复现“没有共同版本”

把两份源文件和 lockfile 复制到新的系统临时目录。在副本中临时创建一个 child module，
让 root 仍要求 `< 6.0.0`，child 却要求 `>= 6.0.0, < 7.0.0`，并由 root 调用它。

~~~powershell
terraform init -upgrade
~~~

预期 init 报告无法找到同时满足全部 constraints 的 AWS provider。错误来自整个 module
requirements graph，不是 LocalStack endpoint。修复方法是让 root/child 声明真实兼容区间，
而不是删除 lockfile反复重试。删除该临时副本。

## Task 3：在原目录放宽但不跨 Major

回到本题目录，把 root 的 AWS constraint 改为 `>= 5.80.0, < 6.0.0`，运行：

~~~powershell
terraform init -upgrade
terraform providers
Get-Content .\.terraform.lock.hcl
~~~

若 registry 可访问，应选择满足范围的较新 `5.x`；若 `5.80.0` 已是缓存中唯一可用版本，
selection 可以不变，但命令语义仍是重新求解。不得升级到 `6.x`。

## Task 4：先审 Schema 差异，再碰 State

~~~powershell
terraform providers schema -json |
  Set-Content -Encoding utf8 .\c50-schema.json
terraform validate
terraform plan '-out=c50-upgrade.tfplan'
terraform show c50-upgrade.tfplan
~~~

重点检查 `aws_s3_bucket` 相关 warning、deprecated attributes 与 plan actions。预期 bucket
为 no-op；若新版 schema 产生差异，先解释差异再决定是否 apply，不能把 provider upgrade
与配置变更混在未经审阅的一次发布里。

## Task 5：应用同一计划并验证可回退流程

当 saved plan 只有可接受动作时：

~~~powershell
terraform apply .\c50-upgrade.tfplan
terraform plan
aws --endpoint-url=http://localhost:4566 s3api head-bucket --bucket tfpro-c50-provider-upgrade
~~~

然后把 constraint 恢复精确 `5.80.0`，运行 `terraform init -upgrade` 让 lockfile 重新选择
`5.80.0`，再 plan。回退 provider selection 后 bucket 仍应存在且无变更。不要手工编辑
lockfile 的 version 或 hashes。

## Task 6：清理并恢复精确 Starter

~~~powershell
terraform destroy -auto-approve
Remove-Item -Force .\c50-schema.json, .\c50-upgrade.tfplan -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
Get-ChildItem -Force
~~~

把 `challenge-50.tf` 恢复到精确 `5.80.0` starter。最终只保留两份源文件，LocalStack 中
`tfpro-c50-provider-upgrade` 不再存在。

## Terraform 1.6 与网络边界

- `init -upgrade` 需要能访问 provider registry 或已配置的 mirror；LocalStack 不提供插件。
- Exam 环境只给有限 Registry 访问，所以要能从错误中快速读出所有 constraints。
- Lockfile 应提交到真实 root module 仓库，但本练习按统一 starter 规则在清理阶段删除。
