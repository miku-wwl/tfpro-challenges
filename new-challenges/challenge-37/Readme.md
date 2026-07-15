# Challenge 37：EC2 Security Group 规则编译器

**难度：95 / 100**  
**考试模式建议时间：65 分钟；首次学习建议时间：110 分钟**

安全团队用 CSV 维护网络规则。你要把弱类型行编译为稳定、可审计的独立 Security Group rule 资源，并拒绝语义冲突。

完成 `starter/`：

1. 规范化 `direction`、`protocol`、端口、CIDR、布尔值和描述；只部署 enabled rows。
2. 独立拒绝重复 `rule_id`、重复规范化 tuple、同方向/协议/CIDR 上的端口区间重叠、非法字段、非法端口边界、非法 CIDR 和零行 CSV；disabled 行不进入规则图。
3. 创建 VPC 与无内联规则的 Security Group；分别使用 `aws_vpc_security_group_ingress_rule` 和 `aws_vpc_security_group_egress_rule`。
4. `for_each` key 必须由 direction/protocol/ports/CIDR 构成，不能使用 CSV 行号；CSV 重排必须为零变更。
5. 用 `data.aws_vpc` 与 `data.aws_security_group` 回读所建网络，并输出排序后的复合 keys、resource addresses 与规则合同。
6. 所有 AWS 资源带 `RunId = var.run_id`；provider 只能使用字面量 `test/test` 与 loopback LocalStack 的 `ec2`、`sts` endpoints。

Canonical tests 精确包含 14 个 run。真实 grader 会审计 plan JSON 和远端 SG rules，验证 data source 回读、CSV 重排、撤销一条远端规则后的 drift 检测与恢复、clean plan、destroy 和零残留。

```powershell
pwsh ./tests/grade.ps1
```
