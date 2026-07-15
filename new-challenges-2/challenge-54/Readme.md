# Challenge 54：Sensitive JSON Policy Compiler 与 Caller/Session Context

难度：**95 / 100**；考试模式 **80 分钟**，首次完整学习 **145 分钟**。评级：**A**。

平台通过一个 `sensitive` JSON string 交付 bucket、policy statements 与轮换 secret。候选配置必须只显式解敏
可公开的 schema/业务字段；原始 secret 不得进入资源、普通 output、CLI plan 或 state，只能以 SHA-256 digest
出现在 sensitive receipt 中。同时要用真实 caller/session context 和 policy-document data sources 编译、挂载 IAM policy。

只修改 `starter/`：

1. 严格校验顶层与 statement schema、contract version、workload/bucket suffix、非空且唯一 key、scope/actions，以及 secret 最小长度。
2. `policy_json` 必须保持 `sensitive = true`；仅对不含 secret 的单独字段显式使用 `nonsensitive`，禁止整体解敏输入。
3. 用稳定 statement key 生成 policy document；statement/action 重排必须生成相同资源图与 policy JSON。
4. 管理一个 force-destroy S3 bucket、IAM role、customer-managed IAM policy 和显式 role-policy attachment；仅允许这四类资源。
5. 使用 `aws_caller_identity`、`aws_iam_session_context` 和两个 `aws_iam_policy_document`，输出公开 ownership contract 与 sensitive policy receipt。
6. provider 只允许 loopback root-origin LocalStack `iam,s3,sts` endpoints、字面量 `test/test`、三项 skip flags 和 path-style S3。
7. grader 使用 Terraform 1.6.6 运行 8 个普通 plan tests，分别动态覆盖顶层与 statement schema；Full 审计 saved-plan 精确四项 create 与 sensitive marker、确认人类可读 plan/state 不含原始 secret、验证真实 S3/IAM；随后在 LocalStack detach policy，要求 saved plan 只 create attachment，修复、clean、destroy 并检查零残留。

说明：saved-plan JSON 是面向机器的高权限接口，可能包含输入变量；grader 只把它用于动作和 sensitivity 元数据审计，不把它作为脱敏的人类输出。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```
