# Challenge 55：LocalStack 可执行的 EC2/LT 滚动 Fleet 合同

难度：**95 / 100**；考试模式 **75 分钟**，首次完整学习 **130 分钟**。评级：**A**。

本题原计划使用 `aws_autoscaling_group`。目标 Docker LocalStack Community 4.14.0 对
`DescribeAutoScalingGroups` 明确返回 license `InternalFailure`，无法完成真实端到端验证。因此本题采用公开
Professional 范围内的可执行替代：以 service-keyed launch template 和 node-keyed `aws_instance` fleet
演练同样的版本滚动、扩缩容、稳定地址和漂移修复；不使用 `terraform_data` 或容量模拟资源。

只修改 `starter/`：

1. 严格解析 `fixtures/catalog-v1.json`，独立阻断顶层/条目 schema、版本、空集合、重复 service/node、非法字段以及 node 引用不存在 service。
2. 用 service name 驱动 `aws_launch_template.release`，用 node ID 驱动 `aws_instance.node`；目录重排必须零变化。
3. 网络由 grader 外建，只能通过 `data.aws_subnet.target` 和 `data.aws_ami.release` 读取；候选不得管理 VPC/subnet。
4. 创建一个真实 `aws_security_group.fleet`；LT 与 instance 必须落实相同 AMI、instance type、SG、release/service user-data 合同。
5. LT 的 user-data 显式 base64；instance 接收原始正文，并设置 `user_data_replace_on_change = true` 与 `create_before_destroy`，使版本升级成为先建后删的真实 replacement。
6. instance tags 必须包含 Node、Service、ReleaseVersion、RunId，并引用真实 launch-template ID。
7. provider 只允许 loopback root-origin LocalStack `ec2,sts` endpoint、字面量 `test/test` 和三项 skip flags。
8. grader 使用 Terraform 1.6.6 运行 8 个普通 plan tests；Full 严格审计 v1 create、v2 LT update/instance replacement、scale-out/in、真实 EC2/LT/SG 回读、reorder、tag drift、clean plan、destroy 与零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```
