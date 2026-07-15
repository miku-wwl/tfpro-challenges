# Challenge 60：三 State 双区域灾备发布与 Promotion/Recovery Capstone

难度：**95 / 100**；考试模式 **120 分钟**，首次完整学习 **210 分钟**。评级：**A**。

这是一个三 state 灾备发布系统，而不是单 root 资源堆叠：`foundation` 在两个 LocalStack region 发布同一制品并创建共享 IAM identity；
`regional` 通过 local `terraform_remote_state` 消费该合同，在两区建立 launch template；`promotion` 同时消费前两层合同，且每次 apply 收敛后只允许
目标 region 存在一个 active EC2。`active_region` 从 primary 切到 DR、再 recovery 回 primary 时，必须得到精确、可审计的动作集合。

只修改 `starter/foundation`、`starter/regional`、`starter/promotion`：

1. foundation 严格解析 `fixtures/release.json`，验证双层 schema、version/generation、artifact key/content/SHA-256；JSON key 重排必须零变化。
2. foundation 用 `aws`/`aws.dr` 创建两区 S3 bucket/object，并创建一次共享 IAM role/profile；输出标量化、可重算的 lineage contract。
3. regional 读取 foundation state，独立拒绝 foreign run、stale generation、schema 缺失或 contract-id 篡改；复用 child module，并把 `aws` 与 `aws.dr` 显式注入 primary/DR。
4. regional 只读取 grader 外建 subnet 与真实 AMI，创建两套 SG/LT；LT 固化对应 bucket/key/digest、shared profile 与 release generation。
5. promotion 同时读取 foundation/regional states，重算两层 contract ID，并拒绝 foreign、stale、断链合同；禁止脚本/state CLI 传递值。
6. promotion 用两个静态、不同 provider 的 `aws_instance` 地址表达 active region，且直接消费对应 AMI/type/subnet/SG/profile 标量；user data 必须携带 artifact 与两层 contract ID。primary→DR 必须精确 `primary delete + dr create`；recovery 必须严格反向。
7. 三个 root 都只允许 loopback root-origin LocalStack endpoints、字面量 `test/test` 与三项 skip flags；禁止 ASG、mock/override、`terraform_data`、candidate script 和 managed VPC/subnet。
8. grader 固定 Terraform 1.6.6，运行 **16 个**普通 plan tests；Full 真实 apply 三个 state，审计每阶段 saved-plan JSON、跨区制品/LT/profile、foreign/stale/schema-missing/contract-tampered 定向拒绝、promotion/failover/recovery 精确 action map、每次收敛后的双区 active EC2 精确计数和真实 tag drift；最后按 promotion→regional→foundation 的 saved destroy plans 逆序销毁并验证 S3/IAM/EC2/LT 以及 grader 外建 AMI/subnet/VPC 双区零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```
