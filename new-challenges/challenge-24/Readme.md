# Challenge 24：三 provider slot 身份诊断

难度：**94/100**　建议时限：**125 分钟**

一个平台模块声明了 `aws.primary`、`aws.dr`、`aws.audit` 三个 provider slot。当前配置虽然能解析，但 root 的 provider 映射和 child 中的资源绑定都发生了“静默串线”：DR bucket、审计 IAM 资源以及 STS 诊断可能都在 primary slot 执行。

## 任务

只修改 `starter/`：

1. root 必须配置三个显式 alias，region 分别来自 `primary_region`、`dr_region`、`audit_region`。
2. 每个 provider 固定使用 `test/test`、三个 `skip_* = true`、S3 path-style，并显式把 S3、IAM、STS endpoint 指向 `localstack_endpoint`。
3. child module 用 `configuration_aliases` 声明三个 slot，root 用 `providers` map 一一对应传入。
4. primary 与 DR bucket 使用相应 slot；IAM role、policy 和 attachment 使用 audit slot。
5. 每个 slot 都读取 `aws_caller_identity` 和 `aws_region`，发布 `provider_diagnostics`，并用 check 限制测试账号。
6. 保存 plan、apply、clean plan、destroy 均须成功。

## LocalStack 的账号限制

LocalStack 默认 STS account ID 是 `000000000000`。它只是本地测试账号，不能证明真实 AWS 的信任策略、组织边界或跨账号权限正确。本题明确禁止 `profile`、共享 credentials 文件、环境中的真实 access key 或 AssumeRole；所有请求只能发往 loopback endpoint。LocalStack 的 IAM 是全局模拟服务，因此这里用 provider slot 和诊断输出来验证归属，而不是把 region 当作真实 IAM 隔离边界。

## 验收

```powershell
pwsh ./tmp2/challenge-24/tests/grade.ps1
```

grader 会做安全扫描、三 alias 契约、带独立 alias 数据的 mock test，以及 LocalStack 的真实 apply/clean-plan/destroy；最后还会直接确认唯一 S3 bucket 与 IAM role 已被删除。
