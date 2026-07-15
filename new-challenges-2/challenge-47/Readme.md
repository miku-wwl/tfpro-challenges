# Challenge 47：无 Mock 的双区域 Provider 路由与真实数据源

难度：**95 / 100**；考纲契合度：**A**。建议考试用时 **65 分钟**，完整学习与复盘 **125 分钟**。

同一个 regional module 分别承载 `primary` 与 `audit` 路由。Grader 会在两个 LocalStack region 中创建网络并注册唯一 AMI；候选配置必须通过显式 provider mapping、真实 `data.aws_ami`、`data.aws_subnet` 与 `data.aws_caller_identity` 证明每条路由没有串区。

## 任务

只修改 `starter/`：

1. 严格解析 `fixtures/routes.json`，只接受 schema v1、恰好 `primary/audit` 两条唯一路由和精确字段集合；输入重排必须是 no-op。
2. 配置 default 与 `aws.audit` 两个 AWS provider；两者均使用 LocalStack `ec2/iam/sts` endpoint、字面量 `test/test` 和三项 skip flag。
3. 两个 module call 必须显式映射 provider：`primary` 使用 `aws`，`audit` 使用 `aws.audit`。Child module 不得声明 provider 配置。
4. Root 只创建 IAM role 与 instance profile。Child 通过路由后的 provider 查询 caller identity、唯一 AMI 和 grader 注入的 subnet，再各创建一台 EC2。
5. 输出完整 `routing_contract`，包含 role/profile、语义 catalog fingerprint，以及两区的 account、region、route、AMI、subnet、VPC 和 instance 信息。
6. 用 HCL precondition 拒绝相同 region、相同 subnet、错误 catalog 和不合法输入；不得使用 mock、override 或合成资源绕过真实查询。

## 资源与考点边界

- 候选 managed resource 精确为 `aws_iam_role`、`aws_iam_instance_profile`、两台 `aws_instance`。
- AWS data source 精确为 `aws_iam_policy_document`、`aws_caller_identity`、`aws_ami`、`aws_subnet`；网络与 AMI 由 grader 创建，不属于候选 state。
- Terraform `~> 1.6`，最终验收固定使用 **1.6.6**；canonical suite 恰好 8 个普通 runs，无 `mock_provider` 或 `override_*`。

## 验收

Grader 审计精确四项 create 的 saved plan，验证双区 AMI/subnet/provider 路由和 catalog 重排 no-op；随后从 LocalStack 手工删除 audit EC2，要求 plan 只重建该地址。最后通过 saved destroy 删除四项资源，并检查 IAM、EC2 与 grader 临时网络/AMI 均无残留。

```powershell
$env:PATH = "$env:TEMP\tfpro-terraform-1.6.6;$env:PATH"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```
