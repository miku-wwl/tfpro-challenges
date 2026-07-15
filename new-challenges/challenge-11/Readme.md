# Challenge 11：LocalStack 双区域 Provider Alias 与可验证路由

难度：**95 / 100**；考纲契合度：**A**；考试模式 **70 分钟**，首次完整学习 **110 分钟**。

一个复用模块必须通过 `aws.primary` 与 `aws.recovery` 两个 provider slot，在两个 AWS region
创建 S3 bucket，并读取各 slot 的 caller identity。starter 故意交换 root 映射、遗漏 child alias
声明和 recovery 资源绑定。只修改 `starter/` 中的 Terraform HCL；不要编写脚本或运维文档。

## 官方大纲 Objective

- **1a / 1b / 1c / 1d**：init、saved plan、apply、clean plan 与 saved destroy；
- **2a / 2b / 2e**：输入 validation、caller identity data source 与输出合同；
- **4a / 4b**：声明和调用带 provider slot 的 child module；
- **5b / 5c / 5d**：provider alias、显式映射、LocalStack 凭证与路由排障。

## 任务

1. root 只定义 `aws.primary` 与 `aws.recovery` 两个 alias，不得依赖隐式 default provider；两者只能使用固定的
   `test/test` LocalStack 凭证，并启用 credential/metadata/account 检查跳过项。
2. 两个 provider 的 S3、STS endpoint 都必须来自 `var.localstack_endpoint`，S3 使用
   path-style。
3. child module 的 `required_providers` 声明
   `configuration_aliases = [aws.primary, aws.recovery]`。
4. module 调用显式映射：`aws.primary = aws.primary`，`aws.recovery = aws.recovery`。
5. 两个 alias 下分别读取 `aws_caller_identity` 并创建不同 bucket；bucket region 必须与 slot 一致。
6. 输出 region/account/bucket 合同，使 grader 能识别 alias 是否被交换。

## 验收命令

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 先验证 endpoint，再在临时目录运行 Terraform 1.6.6 兼容的普通 plan tests；随后保存并审计
真实 LocalStack plan、apply 同一 plan、检查两个 bucket 的区域和 caller contract、验证 clean plan，
最后 apply saved destroy plan 并检查零残留。canonical tests 不使用 `mock_provider` 或 `override_*`。

## 最终不变量

- primary 为 `us-east-1`，recovery 为 `us-west-2`；LocalStack caller account 为测试账号。
- 两个 bucket 名不同，provider slot 没有继承或交换。
- child module 明确声明两个 configuration aliases。
- HCL 只能包含 LocalStack 固定的 `test/test`，不得出现真实 secret。
- saved plan/apply 后真实 bucket location 与 provider slot 一致；destroy 后零残留。

## 安全边界

- 禁止把真实 `.aws/credentials`、环境变量值或 secret 写入仓库。
- endpoint validation 只接受 loopback；不要改成真实 AWS endpoint 后执行 apply。
- `test/test` 只是 LocalStack 协议占位值，不是生产认证方案。

## 官方参考

- https://developer.hashicorp.com/terraform/language/providers/configuration
- https://developer.hashicorp.com/terraform/language/modules/develop/providers
- https://registry.terraform.io/providers/hashicorp/aws/latest/docs#authentication-and-configuration
- https://developer.hashicorp.com/terraform/cli/commands/plan
