# Challenge 58：既有 IAM 接管、声明式 Import 与地址重构

难度：**95 / 100**；考试模式 **75 分钟**，首次完整学习 **130 分钟**。评级：**A**。

grader 先用 legacy `count` 配置创建 `api`、`worker` 两套 IAM role、customer-managed policy 与
attachment。交接时，`api` 三项仍在旧 state lineage 中，必须通过 `moved` blocks 重构到 service-keyed
module；`worker` 三项则被从 state 遗忘但远端仍存在，必须通过 Terraform 1.6 的声明式 `import` blocks
接管。任何 create/delete/replace 都说明迁移合同失败。

只修改 `starter/`：

1. 严格编译两项 identity JSON，独立拒绝错误 schema、错误数量/shape、规范化重名、未知 identity、非法 owner、非法或重复 IAM action。
2. 只允许稳定的 `api`、`worker` semantic keys；JSON 重排不得改变 module/resource identity。
3. child module 创建 IAM role、customer-managed policy 与 attachment；trust/access policy 只能由 `aws_iam_policy_document` 编译，并精确保留 legacy 名称、描述和六项 tags。
4. 用 **6 个 moved blocks** 把两项 identity 的三类 legacy count 地址编码到最终 module 地址；禁止一次性 `terraform state mv`。
5. 用 **6 个 import blocks** 编码 role name、policy ARN 与 attachment composite ID；禁止 CLI `terraform import`。
6. 初始 saved plan 必须证明 `api` 三项从旧地址 no-op move，`worker` 三项 declarative import，且没有 create/update/delete/replace。
7. V2 只能原地更新 `api` policy；外部 detach `worker` 后只能重建该 attachment。随后必须 clean、saved destroy、state empty、LocalStack 零残留。
8. provider 仅使用 LocalStack `iam,sts` endpoints、字面量 `test/test` 与三项 skip flags；候选只允许官方 IAM role/policy/attachment 类型。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

Full grader 固定 Terraform **1.6.6**，先创建真实 legacy 资源，再运行 **11 个**普通、无 mock tests，最后
在同一 state lineage 中审计 saved plan JSON、远端 IAM policy/tag/attachment 语义、reorder、policy rollout、
drift repair、destroy 与 prefix residue。

对应大纲：**1b/1c/1d/1e、2a/2b/2c/2d/2e、3a/3b/3c、5a/5b/5c**。
