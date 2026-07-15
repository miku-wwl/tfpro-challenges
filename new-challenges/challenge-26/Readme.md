# Challenge 26：CSV/JSON 驱动的可审计 IAM 模块目录

难度：**95 / 100**；考纲契合度：**A**；考试模式 **75 分钟**，首次完整学习 **120 分钟**。

安全团队提供身份 CSV 和策略 JSON。你需要把两个弱类型文件规范化为地址稳定的 IAM module graph，并在 plan 阶段阻断重复身份、未知策略和越权策略。CSV 行重排不得改变任何 module/resource 地址。

只修改 `starter/` 中的 Terraform HCL；不得修改 fixtures、tests，也不得编写候选脚本。

## Terraform 任务

1. 用 `csvdecode(file(...))` 与 `jsondecode(file(...))` 读取目录，并规范化 team、workload 和 policy。
2. 以 `team-workload` 为唯一业务 key；先用 grouping mode 检测重复，再构造稳定的 `for_each` map。
3. 独立拒绝未知策略、空 actions/resources、包含 `*` 的 Action，以及不是 scoped AWS ARN 的 Resource。
4. 用 `modules/access-role` 为每项创建：
   - `aws_iam_role`
   - `aws_iam_policy`
   - `aws_iam_role_policy_attachment`
5. trust policy 和权限 policy 必须使用 `aws_iam_policy_document`，禁止手工拼接 JSON。
6. 输出排序后的 `role_keys`；`access_manifest` 必须标记 `sensitive = true`。
7. provider 只能使用字面量 `test/test`，并只暴露 loopback LocalStack 的 IAM、STS endpoints 和三项 skip flags。
8. canonical CSV 与 reordered CSV 必须得到相同地址集合；apply 后 clean plan，真实 attachment 漂移必须被精确修复，destroy 后 IAM 零残留。

本题刻意不要求 permissions boundary、session-duration 领域规则或候选自动化脚本。考点集中在公开 Pro 清单中的 IAM data/resource types、复杂 HCL、模块、稳定身份、plan/apply 与漂移恢复。

## 验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 使用 Terraform **1.6.6** 执行 **8 个普通 `command = plan` runs**，不使用 `mock_provider` 或 `override_*`。真实 LocalStack 阶段审计 saved plan，验证 CSV reorder no-op，带外 detach 一个 policy attachment 后只修复该地址，最后 destroy 并检查零残留。

仅运行静态检查和 canonical tests：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```

## 考纲映射

- **1b / 1c / 1d / 1e**：saved plan、apply、漂移修复与 destroy；
- **2a / 2c / 2d / 2e**：conditions、CSV/JSON functions、`for_each`、复杂输入输出；
- **2b**：`aws_iam_policy_document` data source；
- **4a / 4b**：创建并调用可复用 IAM child module；
- **5b / 5c**：provider 配置和安全的本地测试认证。
