# Challenge 31：CSV 驱动的官方 EC2 发布图

难度：**95 / 100**；考试模式 **70 分钟**，首次完整学习 **120 分钟**。评级：**A**。

grader 在 LocalStack 外部预置一个 VPC 与两个 subnet。候选配置通过官方
`data.aws_subnet` 查询网络，以 `data.aws_ami` 选择镜像，再为目标环境的每个启用 fleet
创建一个 security group、launch template 与 EC2 instance。候选不管理网络、不模拟
Auto Scaling，也不实现自定义 capacity/replica 控制面。

只修改 `starter/`：

1. 严格规范化 CSV 的六字段 schema；独立拒绝空目录、重复 `fleet_id`、非法环境/布尔值、空字段、非法 instance type 与未知 subnet key。
2. `subnet_ids` 由 grader 注入；只用 `data.aws_subnet.selected` 回读 subnet/VPC，不创建 VPC/subnet。
3. `data.aws_ami.selected` 必须查询真实 LocalStack AMI；禁止硬编码 AMI ID。
4. 以 `fleet_id` 作为三个 AWS resources 的唯一 `for_each` key；CSV 重排不得改变地址。
5. security group 与 instance 携带精确 RunId/Owner/FleetId tags；launch template 用稳定名称与输出合同审计，instance tag 还引用真实 launch-template ID 形成图边。
6. 输出排序 fleet IDs、三类精确地址、AMI/subnet/VPC/resource IDs 合同。
7. provider 只使用 LocalStack `ec2,sts` endpoint、字面量 `test/test` 与三项 skip flags；AWS managed/data graph 只用公开 Professional 清单资源。
8. grader 使用 Terraform 1.6.6 运行 10 个无 mock/override canonical runs，随后审计 saved-plan JSON、真实 EC2/LT/SG 属性、reorder no-op、instance tag drift 修复、clean plan、destroy 与零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

对应大纲：**1b/1c/1d/1e、2a/2b/2c/2d/2e、3c、5b/5c**。
