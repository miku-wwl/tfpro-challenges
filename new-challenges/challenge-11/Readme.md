# Challenge 11：LocalStack 多区域 Provider Alias 诊断

## 场景

你接管了一个跨区域对象存储模块。两个 provider 都连接本机 LocalStack，但分别模拟
主区域与灾备区域。child module 必须同时接收 `aws.primary` 与 `aws.recovery` 两个
provider slot。

当前 starter 的 provider mapping 被交换，child module 只声明了一个 alias，诊断手册还
错误建议使用真实 AWS 密钥。你需要修复配置合同，并说明怎样区分“LocalStack 未启动”、
“服务 endpoint 未路由”和“provider 传递错误”。验收使用 mock provider，另可对
LocalStack 执行真实 apply/destroy。

## 官方大纲 Objective

- 1a：初始化包含多个 provider configuration 的工作目录。
- 2a/2c：设计 child module provider contract 与调用方映射。
- 2b：使用 region、caller identity data source 验证运行时身份。
- 3a：配置 AWS provider alias、endpoint 与测试凭证。
- 3b：诊断 endpoint、区域错配和 provider inheritance 问题。

## 任务

1. root 定义默认主区域 provider 与 `aws.recovery` alias；两者只能使用固定的
   `test/test` LocalStack 凭证，并启用 credential/metadata/account 检查跳过项。
2. 两个 provider 的 S3、STS endpoint 都必须来自 `var.localstack_endpoint`，S3 使用
   path-style。
3. child module 的 `required_providers` 声明
   `configuration_aliases = [aws.primary, aws.recovery]`。
4. module 调用显式映射：`aws.primary = aws`，`aws.recovery = aws.recovery`。
5. 两个 alias 下分别读取 `aws_region`、`aws_caller_identity`，并创建不同 bucket。
6. 输出 region/account/bucket 合同，使 CI 能识别 alias 是否被交换。
7. 完成 `AUTH_RUNBOOK.md`：说明 LocalStack health、endpoint 路由、固定测试凭证、
   provider graph 的诊断顺序，以及绝不能替换成真实 secret。

## 验收命令

```powershell
pwsh ./tests/grade.ps1 -CandidateDir ./starter
```

grader 会把根目录 `tests/` 临时复制到候选目录；mock 测试返回不同 region/account，
因此单元验收不依赖 LocalStack。完成题目后还可对本机 LocalStack 执行 apply/destroy。

> Terraform 配置本身只使用 1.6 可用语法。`mock_provider` 属于测试隔离能力；本仓库
> 放宽的 `~> 1.6` 允许当前 Terraform 运行测试。若严格使用 1.6.6，只能改用 LocalStack
> 或真实的隔离测试账号执行同一合同。

## 最终不变量

- primary 为 `us-east-1` / account `111111111111`。
- recovery 为 `us-west-2` / account `222222222222`。
- 两个 bucket 名不同，provider slot 没有继承或交换。
- child module 明确声明两个 configuration aliases。
- HCL 只能包含 LocalStack 固定的 `test/test`，不得出现真实 secret。
- mock plan/test 全部通过且不会发出 AWS API 请求。

## 安全边界

- 禁止把真实 `.aws/credentials`、环境变量值或 secret 写入仓库。
- endpoint validation 只接受 loopback；不要改成真实 AWS endpoint 后执行 apply。
- `test/test` 只是 LocalStack 协议占位值，不是生产认证方案。

## 官方参考

- https://developer.hashicorp.com/terraform/language/providers/configuration
- https://developer.hashicorp.com/terraform/language/modules/develop/providers
- https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration
- https://developer.hashicorp.com/terraform/language/tests/mocking
