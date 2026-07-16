# Challenge 67：Sensitive 不等于不进入 State

## 题目目标

starter 把一个标记为 sensitive 的假 token 写入 S3 receipt。你将先证明普通 CLI 输出虽然
被遮蔽，原始值仍进入远端对象、saved plan 和 Terraform state；然后轮换假 token，并把
最终合同改成只保存 SHA-256 摘要。

考纲对应：sensitive values、输出边界、plan/state 安全、函数与显式解除敏感标记。

## 开始前检查

在 `new-challenges-3/challenge-67` 中执行。全程只能使用 README 给出的假 token，禁止传入
真实密码、API key 或公司 secret：

```powershell
Invoke-RestMethod http://localhost:4566/_localstack/health
terraform version
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

本题会故意生成含假 token 的本地 state、backup 和 plan。它们都是临时敏感制品，必须按
最后的清理步骤删除，不能提交 Git 或发送给 AI。

建议在新开的专用 PowerShell 中练习并在结束后关闭该终端；不要覆盖正在使用的真实
AWS credentials。

## Task 1：观察人类可读输出的遮蔽效果

保持 starter 不变，使用固定假 token 生成并应用 saved plan：

```powershell
terraform init
terraform validate
terraform plan '-var=api_token=lab-token-67-only' '-out=unsafe.tfplan'
terraform show unsafe.tfplan
terraform apply unsafe.tfplan
terraform output
```

预期 `receipt_body` 显示为 sensitive，而不是打印 token。这个结果只证明 Terraform 对
人类可读输出做了遮蔽，不代表底层 state 或远端 S3 对象没有保存原文。

官网入口：[Sensitive data in state](https://developer.hashicorp.com/terraform/language/state/sensitive-data)。

## Task 2：审计 state 与远端对象

把当前 state 拉取到临时审计文件，并搜索假 token：

```powershell
terraform state pull | Out-File -FilePath .\state-audit.json -Encoding utf8
Select-String -Path .\state-audit.json -SimpleMatch 'lab-token-67-only'
$bucket = terraform output -raw receipt_bucket
aws --endpoint-url http://localhost:4566 s3 cp "s3://$bucket/receipts/token.json" -
```

预期 state 搜索和 S3 对象正文都能找到原始假 token。`sensitive = true` 控制显示传播，
不会加密 state，也不会自动把写入资源的值替换成摘要。

## Task 3：把合同改为 hash-only

编辑 `challenge-67.tf`，完成以下变更：

1. 从 `receipt_body` 中删除原始 `token` 字段。
2. 使用 `sha256(var.api_token)` 派生摘要，receipt 只能保存 `token_sha256`。
3. 删除 sensitive 的 `receipt_body` output，改为名为 `token_sha256` 的公开 output。
4. 只有本实验明确允许公开的派生摘要才能通过 `nonsensitive(...)` 解除敏感标记；
   不得对原 token 使用它。SHA-256 不是 secrets manager，也不能保护可被猜测的低熵值。

使用一个新的假 token 模拟凭证轮换，并应用同一个 reviewed plan：

```powershell
terraform fmt
terraform validate
terraform plan '-var=api_token=rotated-lab-token-67-only' '-out=safe.tfplan'
terraform apply safe.tfplan
terraform output -raw token_sha256
terraform state pull | Select-String -SimpleMatch -Pattern 'lab-token-67-only','rotated-lab-token-67-only'
```

最后一个命令预期没有匹配；公开 output 应为 64 个十六进制字符。再次读取 S3 receipt，
正文只能包含摘要和非敏感元数据，不能包含任一 token 原文。

官网入口：[nonsensitive function](https://developer.hashicorp.com/terraform/language/functions/nonsensitive)。

## Task 4：处理已经泄露的历史制品

修复配置不能撤回已经写进旧 plan、state backup 或远端 backend 历史的 secret。先确认当前
state 已经 hash-only，再检查本地历史副本：

```powershell
Get-ChildItem -File terraform.tfstate* | Select-String -SimpleMatch -Pattern 'lab-token-67-only','rotated-lab-token-67-only'
```

如果 `terraform.tfstate.backup` 命中旧假 token，先确认当前 `terraform.tfstate` 可读取且
普通 plan 正常，再删除这个已受污染的实验 backup：

```powershell
terraform plan '-var=api_token=rotated-lab-token-67-only'
Remove-Item .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Remove-Item .\unsafe.tfplan,.\safe.tfplan,.\state-audit.json -ErrorAction SilentlyContinue
```

真实事故中必须轮换 secret，并按远端 backend 的版本保留与事件响应策略处理；不能通过
手工删除团队 state 历史来掩盖泄露。

## Task 5：最终验收与清理

```powershell
terraform plan '-var=api_token=rotated-lab-token-67-only'
terraform destroy -auto-approve '-var=api_token=rotated-lab-token-67-only'
terraform state list
Remove-Item .\unsafe.tfplan,.\safe.tfplan,.\state-audit.json -ErrorAction SilentlyContinue
```

预期清理前 plan 为 `No changes`；destroy 后 state 不包含 managed resource 地址，LocalStack
中不再存在本题 bucket。

## Terraform 1.6 边界

- Terraform 1.6 没有后续版本的 ephemeral value 或 provider write-only argument 能力。
- 在本版本中，避免 secret 进入 state 的可靠做法是不要把原文用于会持久化的资源属性或 output。
- `nonsensitive` 是明确的信任边界，只能用于确认可以公开的派生摘要。

## 最终检查

- 已亲自证明 sensitive 原文会进入旧 state 和远端对象。
- 最终 receipt、output 和当前 state 只包含 SHA-256 摘要。
- 假 token 已轮换，受污染的 plan、审计文件和实验 backup 已清理。
- 没有使用真实 secret。
