# Challenge 15：Subnet Data Source 驱动的稳定安全组规则

难度：**95 / 100**；考纲契合度：**A**；考试模式 **75 分钟**，首次完整学习 **120 分钟**。

grader 会在本机 LocalStack 预置一个隔离 VPC 和带 `Network`/`Tier` tags 的 app、data subnets。
你只修改 `starter/` Terraform HCL：查询既有 subnet，把 CSV 转成稳定的 security groups 与独立 ingress
rule resources。不要创建 VPC/subnet，不要编写候选脚本。

## Terraform 任务

1. 用带 `for_each` 的 `data.aws_subnet.selected`，同时按 `Network` 与 `Tier` tag 查询两个 subnet。
2. `csvdecode` 后显式转换端口和布尔值，只保留目标环境、enabled、ingress 行。
3. 校验环境、字段、端口、协议、tier 与 CIDR/source alias；非法合同独立失败。
4. 每个服务只创建一个 `aws_security_group.workload`，VPC ID 必须来自该服务 tier 的 subnet data。
5. 用一个 `aws_vpc_security_group_ingress_rule.this` block 创建所有规则；业务字段组成稳定 key。
6. CSV 重排必须保持地址和 clean plan；所有 map/list output 必须确定排序。
7. provider 只允许 `test/test`，且 EC2/STS endpoint 必须是 loopback LocalStack。

## 验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 使用 Terraform 1.6.6 的 **6 个普通 plan tests**，不使用 mock/override；真实阶段审计并 apply saved
plan、检查 subnet 查询和远端 SG rules、验证重排 no-op、带外 revoke 一条规则、精确 saved-plan 修复、
clean plan、saved destroy，并删除 grader fixture 后确认 EC2 零残留。

## 考纲映射

- **1b–1e**：saved plan/apply/destroy、真实 drift 与修复；
- **2a–2e**：checks、subnet data source、CSV 函数、稳定 `for_each`、复杂 outputs；
- **3c**：非交互 saved-plan workflow（由 grader 执行）；
- **5b / 5c / 5d**：AWS provider、LocalStack 凭证与 endpoint 排障。

AWS candidate workload 仅使用公开考试资源清单中的 `aws_subnet` data source、`aws_security_group` 与
`aws_vpc_security_group_ingress_rule`。
