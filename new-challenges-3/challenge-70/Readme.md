# Challenge 70：用 TF_LOG 定位 Provider 运行期故障

## 题目目标

starter 的 HCL 和 provider schema 都合法，因此 `init`、`fmt`、`validate` 可以通过；但一个
LocalStack service endpoint 配置错误，第一次 plan 必须在运行期失败。你需要保留失败证据，
用 `TF_LOG` 找到实际请求的服务与端口，只做最小修复，再完成 apply 和清理。

考纲对应：Provider 配置、初始化与验证阶段、运行期排障、环境变量和最小变更修复。

## 开始前检查

确认只有标准 LocalStack 端口 4566 在运行，不要为了让错误配置“碰巧成功”而启动 4567：

```powershell
docker ps --filter 'name=localstack'
Invoke-RestMethod http://localhost:4566/_localstack/health
Get-NetTCPConnection -LocalPort 4567 -ErrorAction SilentlyContinue
```

预期 LocalStack 4566 healthy，4567 没有监听。本题日志只使用 `test/test`，但真实 Provider
日志可能包含 header、路径和敏感值，不能提交 Git 或粘贴到公开渠道。

## Task 1：证明静态检查无法发现运行期 endpoint

保持 `challenge-70.tf` 不变：

```powershell
terraform fmt -check
terraform init
terraform validate
terraform providers
```

预期全部成功，并显示 AWS provider 5.80.0。`init` 负责安装 provider，`validate` 检查 HCL
和 schema；它们不保证每个远端 API endpoint 可连接。

## Task 2：复现第一次 plan 失败

```powershell
terraform plan
```

预期命令非零退出，错误上下文指向 `data.aws_caller_identity.runtime` 或 STS
`GetCallerIdentity`，并包含连接失败或无法访问 4567。不要删除 data source、不要把 output
写死成 `000000000000`，也不要增加重试来掩盖根因。

## Task 3：使用 TF_LOG 收集最小诊断证据

在同一个 PowerShell 会话中设置日志级别和临时日志文件，再复现一次失败：

```powershell
$env:TF_LOG = 'TRACE'
$env:TF_LOG_PATH = (Join-Path (Get-Location) 'terraform-trace.log')
terraform plan
Select-String -Path .\terraform-trace.log -Pattern 'GetCallerIdentity','sts','4567'
```

预期日志能把失败请求关联到 STS 和错误端口 4567。只保留能证明根因的观察结论；不要把
整份 TRACE 日志长期保存。

官网入口：[Terraform debugging](https://developer.hashicorp.com/terraform/internals/debugging)。

## Task 4：做最小 Provider 修复

编辑 `challenge-70.tf` 的 AWS provider，只修正失败服务的 endpoint，使它与当前
LocalStack root origin `http://localhost:4566` 一致。不得删除显式 endpoints、dummy
credentials、三个 skip flags 或 caller identity data source。

先关闭日志环境变量并删除临时日志，再重新检查：

```powershell
Remove-Item Env:TF_LOG -ErrorAction SilentlyContinue
Remove-Item Env:TF_LOG_PATH -ErrorAction SilentlyContinue
Remove-Item .\terraform-trace.log -ErrorAction SilentlyContinue
terraform fmt
terraform validate
terraform plan
```

预期 plan 成功，读取 LocalStack caller identity，并只计划创建一个 IAM role。

## Task 5：应用、验证幂等并清理

```powershell
terraform apply -auto-approve
terraform output runtime_contract
terraform plan
terraform destroy -auto-approve
terraform state list
Remove-Item .\terraform-trace.log -ErrorAction SilentlyContinue
```

预期 account ID 为 LocalStack 测试账号 `000000000000`，apply 后的第二次 plan 为
`No changes`；destroy 后 state 为空，日志文件不存在。

## Terraform 1.6 边界

- Terraform 1.6 的 `init` 和 `validate` 不执行本题的 STS data source 请求；远端连通性要到 plan 才暴露。
- `TF_LOG` 与 `TF_LOG_PATH` 是 CLI 进程环境变量，不属于 HCL，也不应永久写入 shell profile。
- 本题不使用 mock、override 或跳过 caller identity 来伪造成功，修复必须经过真实 LocalStack plan。

## 最终检查

- 未修改 starter 时，init/validate 成功而 plan 按预期失败。
- TRACE 证据明确指向 STS 与错误端口，而不是凭猜测修改。
- 只修复一个 endpoint 后 plan/apply/clean plan 均成功。
- destroy 后 state 为空，TF_LOG 环境变量和日志文件均已清理。
