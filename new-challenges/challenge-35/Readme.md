# Challenge 35：双 State 跨区域计算合同交付

难度：**96 / 100**；考试模式 **75 分钟**，首次完整学习 **135 分钟**。评级：**A**。

平台把网络所有权留给外部团队，并将 Terraform 拆成 `foundation` 与 `fleet` 两个独立 root。foundation 必须查询 grader 预置的 primary/DR subnet，在正确 provider slot 中创建安全组，并发布 IAM 与网络合同；fleet 只能通过真实 S3 remote state 消费该合同，再把 CSV 目录路由到两个静态 regional module。

只修改 `starter/`：

1. 两个 root 都使用空的 partial S3 backend；所有 backend 参数由 grader 在 `init` 时注入，禁止 local state 交接。
2. foundation 用 default/`aws.dr` 的 `data.aws_subnet` 接管外部网络，只创建两个 `aws_security_group`、一个 IAM role 与一个 instance profile；禁止管理 VPC/subnet。
3. foundation 发布 `contract_version = 1` 的 `compute_contract`，并拒绝相同 region、相同 subnet、跨 run 或不完整合同。
4. fleet 仅用 S3 `terraform_remote_state` 消费 foundation；查询双区 `data.aws_ami`，并把 default/`aws.dr` 显式传给两个静态 child module。
5. 规范化六列 CSV：`name,environment,location,instance_type,owner,enabled`；独立拒绝 schema、布尔值、字段格式、未知 location、重复 `name@location` 与无目标环境启用项。
6. 每个启用 fleet 用稳定 `name@location` key 管理一个 launch template 与一个 EC2 instance；CSV 重排不得改变任何地址。
7. instance 必须直接落实 AMI、类型、subnet、安全组与 instance profile，并用 tag 记录对应 launch-template ID；不得使用 capacity/replica 模拟、`terraform_data`、`ignore_changes` 或候选脚本。
8. 输出排序 fleet keys、精确资源地址、owner 分组、AMI IDs 与完整 fleet contract。
9. grader 审计 saved-plan JSON 后依次 apply，回读真实双区 EC2/LT/IAM 属性，验证 reorder 零变化、单 tag drift 精确修复、两个 clean plan、fleet→foundation 逆序 destroy 与 LocalStack 零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

## Professional 大纲定位

覆盖 partial S3 backend、remote-state contract、provider alias/static module routing、data source、IAM role/profile、security group、launch template、EC2、CSV collection、稳定 `for_each`、saved plan、drift 与 destroy。所有 AWS 资源类型均位于 Terraform Professional 公布范围，难度评级 **A（96/100）**。
