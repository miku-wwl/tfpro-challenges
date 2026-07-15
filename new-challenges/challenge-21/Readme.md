# Challenge 21：既有网络上的 CSV 安全规则工厂

难度：**96 / 100**；考纲契合度：**A**；考试模式 **80 分钟**，首次完整学习 **130 分钟**。

平台已经创建 VPC 和三个 subnet，并把按业务 key 索引的 subnet ID map 交给你。你不能在候选配置中管理 VPC/subnet；任务是用公开清单中的 `aws_subnet` data source 回读真实 CIDR/VPC 身份，再把 CSV 规则编译为稳定的 security-group graph。

只修改 `starter/` 中的 Terraform HCL；grader 会外部创建和清理网络。不得修改 fixtures/tests 或编写候选脚本。

## Terraform 任务

1. 严格验证 environment、name/run ID、loopback endpoint，以及 subnet map 精确包含 `public-a`、`private-a`、`data-a`。
2. 用 `csvdecode(file(...))` 显式转换 bool、number 和 string；先过滤目标环境及 `enabled=true`。
3. 用 grouping mode 检测重复 `rule_id`，再以 `rule_id` 构造稳定 `for_each` map；禁止 CSV 行号。
4. 通过 `data.aws_subnet.managed` 回读三个既有 subnet；security group 的 VPC ID 以及 rule CIDR 都必须来自 data source。
5. 只管理公开考试清单中的：
   - `aws_security_group`
   - `aws_vpc_security_group_ingress_rule`
6. 通过 output preconditions 独立阻断重复 ID、未知 subnet 引用、非法协议/端口、同组 owner 冲突和非法字段。
7. 输出排序后的 active IDs、owner 分组、精确 managed addresses 和包含 provider-derived subnet CIDRs/VPC ID 的 topology contract。
8. canonical 与 reordered CSV 必须得到相同地址和 clean plan；disabled/其他环境行不得进入 graph。
9. grader 带外删除 `api-from-web` 规则后，saved repair plan 只能重建该地址。
10. saved destroy 后候选管理的 groups/rules 必须零残留；外部 VPC/subnets 由 grader 随后清理。

本题不使用 `aws_vpc`、`aws_subnet` resource、`data.aws_vpc` 或 `terraform_data`。相较普通 CSV 题，它强调外部 subnet-ID 合同、官方 data source 回读、引用完整性和 owner 分组。

## 验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 使用 Terraform **1.6.6** 执行 **10 个普通 plan runs**，无 `mock_provider` / `override_*`；canonical tests 和 E2E 都读取真实 LocalStack subnet data。

仅运行 canonical tests（grader 仍会创建并清理临时网络）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```

## 考纲映射

- **1b / 1c / 1d / 1e**：saved plan、真实规则漂移、repair 和 destroy；
- **2a / 2c / 2d / 2e**：preconditions、CSV functions、稳定 `for_each`、复杂合同；
- **2b**：公开清单中的 `aws_subnet` data source；
- **5b / 5c**：安全 LocalStack provider 配置。
