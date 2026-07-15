# Challenge 43：JSON 驱动 IAM 权限目录编译器

难度：**95 / 100**；考试模式 **70 分钟**，首次完整学习 **130 分钟**。评级：**A**。

将严格 JSON 权限目录编译成 IAM role、customer-managed policy 与 attachment。重点不是资源数量，而是稳定身份、顺序无关的 canonical policy、最小权限语义拒绝，以及 saved-plan 和远端 IAM 证据的可审计性。

只修改 `starter/`：

1. 顶层只允许 `schema_version=1` 与 1..10 个 entries；entry/statement 必须是精确 key 集。
2. id/owner 必须是 3..24 位 lowercase kebab-case；显式拒绝重复 id。
3. trust services 必须非空、排序、唯一并符合 AWS service principal 格式。
4. statements 以 SID 排序；拒绝空列表、重复/非法 SID、非 `Allow` effect。
5. actions/resources 排序且唯一；拒绝非法 action、任何 wildcard action、全局 `*` 和非 ARN resource。
6. 只能用 `aws_iam_policy_document` 编译 trust/permission JSON，禁止手工 `jsonencode` policy。
7. 每个稳定 id 创建 role、policy、attachment，写入 RunId/EntryId/Owner/ManagedBy 标签。
8. 输出 canonical directory、实际 IAM 名称/ARN 与 caller/session identity 合同。
9. reordered JSON 必须 clean；updated fixture 只能原地更新 `artifact-reader` policy；外部 attachment drift 只能重建一个 attachment。
10. provider 仅配置 `iam,sts` LocalStack endpoints，字面量 `test/test` 与三项 skip flags。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 在官方 Terraform 1.6.6 上执行 **21 个 normal plan runs**，随后审计六资源 saved create/apply、IAM/STS 远端 policy 语义、reorder clean、单 policy 升级、attachment drift 恢复、再次 clean、saved destroy 和 IAM 零残留。

候选仅允许 `aws_iam_role`、`aws_iam_policy`、`aws_iam_role_policy_attachment` 及官方 caller/session/policy-document data sources。
