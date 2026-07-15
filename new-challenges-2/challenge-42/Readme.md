# Challenge 42：三 Provider Slot 的 S3/IAM 可审计路由

难度：**95 / 100**；考试模式 **70 分钟**，首次完整学习 **125 分钟**。评级：**A**。

一个 child module 必须同时接收 primary、DR 与 audit 三个 AWS provider slot。每个 slot 都创建一组 S3 bucket 与 IAM role；grader 将从 saved-plan JSON 的 configuration tree 审计每个资源实际绑定的 provider key，不能仅凭名称或 region 推测。

只修改 `starter/`：

1. 解析并规范化 `fixtures/routes.json`，独立拒绝错误 schema、重复 route、非法字段、缺少/禁用 slot 和重复 suffix。
2. root 声明 `aws.primary`、`aws.dr`、`aws.audit`，均使用字面量 `test/test`、三项 skip flags 和仅 `iam,s3,sts` 的 LocalStack endpoints。
3. child 通过 `configuration_aliases` 声明 `aws.dr` 与 `aws.audit`，root 必须显式映射三个 slot。
4. 每个 slot 创建一只 `force_destroy` bucket 与一只 EC2 trust role；资源、caller identity 与 policy document 都必须绑定正确 provider。
5. 输出排序 route keys、六个资源地址、bucket/role/caller 合同；JSON 行重排必须 clean。
6. 修复 grader 制造的 audit role tag drift，且 saved repair plan 只能更新该 role。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

Full grader 固定使用 Terraform 1.6.6 与真实 LocalStack，审计 initial saved-plan action map 与 provider_config_key、验证三个 bucket 的 region、IAM role/caller 合同、reorder clean、单资源 drift repair、post-repair clean、saved destroy 和 S3/IAM 零残留。

候选仅允许 `aws_s3_bucket`、`aws_iam_role`，以及 `aws_caller_identity`、`aws_iam_policy_document` data sources。
