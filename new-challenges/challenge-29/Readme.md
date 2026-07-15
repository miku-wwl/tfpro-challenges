# Challenge 29：双区域嵌套模块制品与 IAM 合同

难度：**96 / 100**；考纲契合度：**A**；考试模式 **85 分钟**，首次完整学习 **135 分钟**。

服务目录来自 CSV。每个目标环境中启用的服务都要在 primary 和 DR 各获得一个 S3 artifact bucket，以及一套只允许访问该 bucket 的 IAM role、customer-managed policy 和 attachment。模块层次固定为 root → replication → regional；两个 provider slot 必须跨每一层显式声明和传递。DR 还要消费按服务 key 发布的 primary bucket 合同。

只修改 `starter/` 中的 Terraform HCL；不得编写候选脚本或修改 fixtures/tests。

## Terraform 任务

1. 用 `csvdecode(file(...))` 规范化服务名、owner、environment、retention 和 enabled。
2. 只选择目标环境且启用的服务，以规范化 service name 作为稳定 `for_each` key；CSV reorder 必须零变化。
3. 通过 output preconditions 独立拒绝空选择、重复服务名、非法 name/owner 和非法 retention。
4. root 配置 `aws.primary`、`aws.dr`；调用 replication 时将两个 slot 一一映射。
5. replication 声明 `configuration_aliases = [aws.primary, aws.dr]`，regional 声明 `aws.workload`，并在两层边界显式传递。
6. regional 对每个服务创建公开 Pro 清单中的：
   - `aws_s3_bucket`
   - `aws_iam_role`
   - `aws_iam_policy`
   - `aws_iam_role_policy_attachment`
   - trust/access `aws_iam_policy_document` data sources
7. DR 的 `peer_buckets` 必须由 `module.primary.contracts` 按 key 推导；禁止跨模块直接引用资源。
8. 输出双区域合同、排序的 service keys 和按 owner 分组的服务。
9. provider 只能使用字面量 `test/test`，只暴露 IAM/S3/STS loopback endpoints、S3 path-style 和三项 skip flags。
10. saved apply 后，reordered CSV 为 no-op；grader 带外 detach DR api attachment，repair plan 只能重建该地址；saved destroy 后 LocalStack 零残留。

本题不再使用 DynamoDB、SNS、`aws_region` 或 `terraform_data`。难点完全落在公开考试资源、复杂 HCL、nested modules、provider aliases、稳定身份和漂移恢复上。

## 验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 使用 Terraform **1.6.6** 执行 **8 个普通 plan tests**，不使用 `mock_provider` 或 `override_*`，随后完成真实 LocalStack saved-plan E2E。

仅运行静态检查和 canonical tests：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```

## 考纲映射

- **1b / 1c / 1d / 1e**：saved plan、apply、真实漂移修复与 destroy；
- **2a / 2b / 2c / 2d / 2e**：preconditions、policy data、CSV functions、`for_each`、复杂合同；
- **4a / 4b**：两层 child modules 和显式接口；
- **5b / 5c / 5d**：provider aliases、认证与 provider routing 排错。
