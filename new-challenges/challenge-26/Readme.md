# Challenge 26：CSV/JSON 驱动的 IAM 访问目录

难度：**94/100**，建议限时 105 分钟。

安全团队交付了 `fixtures/access-catalog.csv` 和 `fixtures/policy-catalog.json`。请把它们转换为可审计、地址稳定的 IAM 访问目录。所有 AWS API 只能访问本机 LocalStack；本题验证 Terraform 建模能力，**LocalStack 不会真实验证 AWS IAM 的授权边界语义**，因此仍需用 HCL checks 明确策略约束。

## 任务

1. 只允许 `dev`、`stage`、`prod` 环境，并限制 `localstack_endpoint` 为 loopback HTTP(S) 地址。
2. 解码 CSV 与 JSON，以 `team-workload`（规范化为小写）作为稳定 key；重排行不得改变 module/resource 地址。
3. 检测重复身份、未知策略名、空 action/resource、非法 session duration，以及任何包含通配符的 action（例如 `"*"` 或 `"s3:*"`）。这些错误必须由资源 precondition 在 plan 阶段阻断，不能只产生 check warning。
4. 在根模块创建统一 permissions boundary；调用 `modules/access-role`，为每个目录项创建 IAM role、customer-managed policy 与 attachment。
5. 模块必须用 `aws_iam_policy_document` 构造 assume-role 与权限文档，不能手写拼接 JSON。
6. 输出稳定排序的 `role_keys`；`access_manifest` 必须标记 `sensitive = true`。
7. 修复后运行：

```powershell
pwsh ./tests/grade.ps1
```

grader 会复制候选目录到隔离临时目录，运行格式化、初始化、验证、canonical mock tests，并在 LocalStack 中执行 apply、clean plan 与 destroy。不要修改 fixtures 或 tests。

## LocalStack 说明

默认 endpoint 为 `http://localhost:4566`，凭证固定为 `test/test`。本题不需要真实 AWS 账号；请勿加入 profile、真实 access key 或公网 endpoint。
