# Challenge 34：测试驱动的 AWS 模块与 Provider 故障诊断

难度：**96 / 100**　建议用时：**120 分钟**

## 场景

一个双区域诊断模块同时查询 AMI、调用者身份和 IAM session issuer，并在 primary、DR
各创建一个诊断 VPC。当前代码在模块 provider 合同、data source 路由和测试替身上都有
缺口。单看 HCL 很难判断“查错区域”和“mock 掩盖真实故障”的区别。

## 任务

1. root 只配置 `aws.primary` 和 `aws.dr`，二者都必须使用 LocalStack `test/test`。
2. child module 用 `configuration_aliases` 声明两个 provider slots。
3. root 的 module call 显式传递两个 aliases，不允许 child 隐式继承默认 provider。
4. 每个区域分别查询 `aws_ami`、`aws_caller_identity`、
   `aws_iam_session_context`，并显式绑定正确 slot。
5. 以 root `output.diagnostic_guard` 的独立 preconditions 验证区域、AMI ID、账号和
   issuer ARN；guard 必须在任何真实资源创建前阻断坏数据。
6. 使用 `mock_provider` 和 run-level `override_data` 精确替换 data source。
7. 所有负测统一以 `output.diagnostic_guard` 作为 `expect_failures` target；分别证明
   same-region、非法 AMI、非法账号、空 issuer 和格式非法 issuer 会失败。
8. 从 saved plan JSON 核验 8 个 AWS managed/data blocks 的
   `provider_config_key`，不能只依赖输出猜测路由。
9. 在真实 LocalStack EC2/IAM/STS 上 apply、重复 plan、destroy 并核验无 VPC 残留。

## 诊断 fixture

`fixtures/mock-diagnostics.json` 是 canonical test 的预期数据合同。修改 mock 或模块输出时，
必须保持 primary 与 DR 的 AMI、caller 和 issuer 可独立诊断。

## 验收

```powershell
pwsh ./tests/grade.ps1
```

grader 精确执行 7 个 Terraform tests（2 个正向/隔离用例与 5 个独立负测），随后解析
真实 saved plan JSON，再完成 LocalStack EC2/STS/IAM 端到端验证。任何非 loopback
endpoint 都会在网络调用前被拒绝。

## Professional 大纲

覆盖 module/provider contracts、configuration_aliases、data source troubleshooting、
Terraform test mocks/overrides、expected failures、plan JSON、依赖图与 provider 诊断。
