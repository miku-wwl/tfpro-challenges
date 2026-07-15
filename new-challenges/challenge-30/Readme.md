# Challenge 30：三 State 官方 AWS 发布链

难度：**96 / 100**；考试模式 **75 分钟**，首次完整学习 **135 分钟**。评级：**A**。

这是一个严格顺序的三 state 发布链：`foundation` 创建 EC2 workload IAM role/profile 并发布
版本化身份合同；`platform` 只能通过 `terraform_remote_state` 消费该合同，在 primary/DR
创建两个 release bucket；`workloads` 再消费两份合同，把 CSV 展开成稳定的
`name@location` S3 object graph。所有 AWS 调用走 LocalStack。

只修改 `starter/`：

1. 三个独立 root 均声明空 partial S3 backend，并约束 Terraform `~> 1.6` 和 AWS `~> 5.100`；child module 不配置 provider。
2. foundation 只使用公开考试清单中的 caller identity、IAM policy document、IAM role 与 instance profile，发布 `identity_contract` v1。
3. platform 只通过 S3 `terraform_remote_state` 读取 foundation，使用 default/`aws.dr` 创建两个官方 `aws_s3_bucket`，发布 `platform_contract` v1。
4. workloads 只通过两份 remote state 读取合同；规范化 CSV schema/fields/boolean/locations/port，拒绝重复 `name@location`，只部署目标环境启用行。
5. workloads 用两个静态 module blocks 把 primary 与 DR object maps 交给同一个 child，并显式传递 default/`aws.dr`。child 只创建官方 `aws_s3_object`。
6. 合同版本、region、run_id、role/profile、bucket/locations 必须由 blocking output preconditions 校验；禁止 `terraform_data`、mock/override 与候选脚本。
7. CSV 重排必须零地址变化；object JSON、metadata、tags 必须承载 identity/platform contract 和 workload 字段。
8. grader 使用 Terraform 1.6.6 运行 8 个真实-provider canonical runs，并在同一三-state lineage 上执行 saved-plan JSON gate、按序 apply、真实 S3 回读、reorder、单 object drift 修复、clean plans、逆序 destroy 与零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

对应大纲：**1b/1c/1d/1e、2a–2e、3a/3c/3d、4a/4b、5b/5c/5d**。AWS managed/data graph 仅使用公开 Professional 清单资源。
