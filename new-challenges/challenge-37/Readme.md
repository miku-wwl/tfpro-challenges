# Challenge 37：官方 AWS Security Group Rule 编译与漂移修复

难度：**95 / 100**；考试模式 **65 分钟**，首次完整学习 **110 分钟**。评级：**A**。

grader 会在 LocalStack 外部预置 VPC/subnet，候选配置只能用官方清单中的
`data.aws_subnet` 查询网络，并用 `aws_security_group` 与官方独立 ingress rule 资源
把弱类型 CSV 编译为稳定规则图。预置网络不进入候选 state，也不得由候选创建。

只修改 `starter/`：

1. 规范化 protocol、ports、CIDR、description 与 enabled；只部署 enabled rows。本题全部规则都是 ingress。
2. 独立校验精确 CSV schema、非空目录、rule_id、协议、端口、CIDR、description、布尔值、重复 ID 与重复 tuple；不实现自定义区间重叠算法。
3. `subnet_id` 由 grader 注入；用 `data.aws_subnet.selected` 获取真实 VPC ID，禁止 managed VPC/subnet。
4. 创建一个无 inline rules 的 `aws_security_group.rules`，并用规范化 tuple 作为 `aws_vpc_security_group_ingress_rule.rule` 的稳定 `for_each` key。CSV 重排必须零地址变化。
5. 输出排序 keys、精确 ingress addresses，以及 subnet/VPC/规则合同。
6. AWS provider 只配置 LocalStack `ec2,sts`、字面量 `test/test` 和三项 skip flags；候选只包含 Terraform HCL。
7. grader 使用 Terraform 1.6.6 运行 12 个无 mock/override 的 plan runs，然后审计 saved-plan JSON、真实 ingress rules、reorder no-op、远端规则删除后的漂移修复、clean plan、destroy 与零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

对应大纲：**1b/1c/1d/1e、2a/2b/2c/2d/2e、3c、5b/5c**。AWS managed/data graph 均取自公开 Professional 资源清单。
