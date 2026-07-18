# Challenge 53：Sensitive 只遮蔽界面，不会自动离开 Plan 与 State

Starter 故意把一个 sensitive token 写入 S3 object。正常 CLI output 会遮蔽它，但 provider
仍必须接收内容，Terraform state 与 saved plan 也可能保存它。本题通过本机临时假值审计每个
边界，再把发布合同收敛为 hash-only，并判断何时应让 Vault 等外部秘密系统完全绕开 Terraform。

## 官方考试目标

- **2f**：Analyze best practices for managing sensitive data, such as using Vault for secrets management
- **3c**：Use the Terraform workflow in automation
- **5c**：Manage provider authentication

只使用下面的练习假值；不要把真实 token 放进 shell history、`.tf`、plan 或 state。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-53
$env:TF_VAR_release_token = "local-only-c53-token"
terraform init
terraform plan '-out=c53-unsafe.tfplan'
terraform show .\c53-unsafe.tfplan
~~~

人类可读 plan 应把 sensitive expression 遮蔽，但这不等于 plan file 中没有值。此时不要把
`c53-unsafe.tfplan` 上传或提交。

## Task 1：应用并观察 CLI 遮蔽

~~~powershell
terraform apply .\c53-unsafe.tfplan
terraform output
terraform output manifest
~~~

Output 应显示 sensitive 标记而不是 token。只有显式使用 `terraform output -raw` 或
`-json` 才可能取回敏感值；自动化日志不应为了方便绕过遮蔽。

## Task 2：审计 State 与远端对象

仅在本机练习目录执行：

~~~powershell
terraform show -json |
  Set-Content -Encoding utf8 .\c53-state-audit.json
Select-String -SimpleMatch $env:TF_VAR_release_token .\terraform.tfstate, .\c53-state-audit.json
aws --endpoint-url=http://localhost:4566 s3api get-object --bucket tfpro-c53-sensitive-audit --key release/manifest.json .\c53-object.json
Select-String -SimpleMatch $env:TF_VAR_release_token .\c53-object.json
~~~

预期 state/JSON 和远端 object 能找到假 token。这证明 `sensitive = true` 是显示与传播标记，
不是加密、redaction 或 secret manager。

## Task 3：审计 Saved Plan 的保管边界

把环境 token 改为另一个至少 12 字符的假值，生成新 saved plan，不应用：

~~~powershell
$env:TF_VAR_release_token = "rotated-local-c53-token"
terraform plan '-out=c53-rotate.tfplan'
terraform show -json .\c53-rotate.tfplan |
  Set-Content -Encoding utf8 .\c53-plan-audit.json
Select-String -SimpleMatch $env:TF_VAR_release_token .\c53-plan-audit.json
~~~

即使终端 diff 被遮蔽，machine-readable plan 仍可能包含敏感值。因此 CI 的 plan artifact
需要访问控制、短保留期和安全删除；不能当普通构建日志。

## Task 4：改成 Hash-Only 发布合同

修改 object 内容，使其只包含 release 与 token 的 SHA-256 digest，不再包含 token 本身；
output 也只发布 bucket、key 与 digest。评估 digest 是否可用 `nonsensitive` 暴露：高熵随机
token 的 hash 通常可作指纹，低熵密码的 hash 仍可能被离线猜测。

~~~powershell
terraform fmt
terraform validate
terraform plan '-out=c53-hash.tfplan'
terraform apply .\c53-hash.tfplan
terraform output
~~~

重新下载 object 并搜索两个历史假 token，均不应出现。注意旧 state/plan/audit files 已经
泄露，修改当前配置不会自动擦除历史制品。

## Task 5：判断 Vault/外部秘密系统的正确边界

与结对 AI 对以下三种设计逐一判断：

1. Terraform 从 Vault 读取完整 secret 再写给 resource；
2. Terraform 只写 Vault secret path/role，workload 在运行期取 secret；
3. CI 把 secret 作为 `TF_VAR` 传入并长期保存 plan artifact。

说明哪些设计仍会让 secret 进入 Terraform state，哪一种能让 Terraform 只管理引用。不要为
本题安装 Vault provider；官方目标是分析最佳实践，不是把未配置的 Vault 伪装成 LocalStack。

## Task 6：销毁并删除所有敏感制品

先使用当前环境值销毁：

~~~powershell
terraform destroy -auto-approve
Remove-Item Env:TF_VAR_release_token
Remove-Item -Force .\c53-*.tfplan, .\c53-*.json -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
Get-ChildItem -Force
~~~

确认 bucket 已删除，把 `challenge-53.tf` 恢复为故意不安全的 starter，最终只保留两份源文件。

## 安全边界

练习值也只应留在本机。真实系统还要保护 remote state、backend metadata、crash logs、
provider logs、shell history 和备份；仅给 output 加 `sensitive` 远远不够。
