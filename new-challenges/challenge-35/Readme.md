# Challenge 35：双 State 计算平台灾备发布 Capstone

难度：**98 / 100**　建议用时：**160 分钟**

## 场景

计算平台拆成 `foundation` 与 `fleet` 两个独立 root module、两份独立 state。
foundation 在 primary/DR 两个区域创建 VPC、subnet、security group，并管理 EC2 的
IAM role 与 instance profile，再发布显式版本的计算合同。fleet 只能通过
`terraform_remote_state` 消费该合同，根据 CSV 创建双区域 launch template 和 EC2 fleet。

LocalStack Community 不提供可用于本实验端到端验收的 Auto Scaling API，因此本题采用
安全降级模型：`desired_capacity` 被展开为稳定的 `name@location#NN` EC2 replica；每个
`name@location` 仍有独立 launch template。这样可以真实验证 provider 路由、容量边界、
资源身份、漂移恢复和灾备发布，而不会用静态假通过替代云端行为。

LocalStack 4.x 的 `DescribeInstances` 不会回填 launch-template 关联，而且不会完整模拟
template 中 instance type、instance profile 与 security group 的继承。grader 因此同时验证：
comment-aware/balanced HCL 与 saved-plan JSON 中的 launch-template source、LocalStack
持久化的 template 完整字段，以及真实实例的 AMI、区域、subnet 和 tag。module 只对无法
回读的 `launch_template` 字段使用 `ignore_changes`，并用 revision sentinel 保留 template
升级触发实例替换的语义；launch template 还只忽略 LocalStack 将顶层 tags 镜像成额外
`tag_specifications` 的回读噪声。这是本地模拟器能提供的最强可复现实证；在 AWS 上应再
增加实例侧全部继承属性断言。

## 任务

1. 为两个 root 配置 literal `test/test`、loopback LocalStack endpoint，以及明确的
   default/`aws.dr` provider；child module 不得定义 provider。
2. foundation 创建两套 VPC/subnet/security group 和一套 EC2 IAM role/instance
   profile，输出 `contract_version = 1` 的 `compute_contract`。
3. foundation 必须拒绝相同区域和相同 VPC CIDR。
4. fleet 通过 local `terraform_remote_state` 读取合同；不得直接引用 foundation 资源。
5. fleet 在两个 provider 上分别查询 `aws_ami`，用两个静态 module block 明确传递
   `aws` 与 `aws.dr`。
6. 规范化并筛选 CSV，以 `name@location` 为 fleet key；以
   `name@location#NN` 为 replica key。CSV 重排行不得改变任何资源地址。
7. 拒绝未知 location、重复 fleet key、非法名称、合同版本不兼容、合同区域错配，以及
   `min <= desired <= max` 不成立或容量超限的输入。
8. 每个区域 module 创建 launch template 和期望数量的 EC2 instance，并输出可审计的
   fleet contract、replica IDs 与 owner 分组。
9. 使用 saved plan 发布；apply 前解析 plan JSON 并拒绝 delete/replace。定向制造 tag drift，
   通过 refresh plan 恢复，再证明两个 root 的重复 plan 均为空。
10. 严格按 fleet → foundation 逆序 destroy，并确认 LocalStack 无本次资源残留。

## 验收

确保 LocalStack edge endpoint 位于 `http://localhost:4566`，然后运行：

```powershell
pwsh ./tests/grade.ps1
```

grader 会隔离复制 candidate，运行 foundation 3 个、fleet 9 个 canonical mock tests，再执行真实 LocalStack 双 state
端到端流程。失败和成功路径都会执行逆序清理，仓库目录不会留下 state、plan 或
`.terraform`。

## Professional 大纲

综合覆盖 state 边界、remote-state contract、provider graph、module interface、复杂
collection、稳定资源身份、执行计划 JSON、saved-plan automation、drift/refresh、灾备发布、
幂等性和安全清理。它是一道接近真实平台交付流程的综合实操题。
