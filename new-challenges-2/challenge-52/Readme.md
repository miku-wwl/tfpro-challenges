# Challenge 52：Security Group Rules 从 Count 到稳定 Key 的零动作迁移

难度：**95 / 100**；考试模式 **75 分钟**，首次完整学习 **135 分钟**。评级：**A**。

旧配置用 `count` 管理一个 security group 与三条独立 ingress rule。现在必须把它们迁入 child module，并以 CSV
中的业务 key 驱动 `for_each`。真实规则不能因地址重构而新增、删除或替换；迁移映射必须留在 HCL 中接受审查。

只修改 `starter/`：

1. 严格解析 `fixtures/rules.csv`，独立拒绝错误 header、空清单、重复 key 与非法 protocol/port/CIDR/description。
2. child module 精确管理一个 `aws_security_group.this` 和三条 `aws_vpc_security_group_ingress_rule.this[key]`；禁止 inline ingress/egress。
3. 使用四个 `moved` blocks：SG 一项，以及 `legacy[0..2]` 到 `admin/api/metrics` 三个稳定地址；禁止 `terraform state mv`。
4. CSV 行重排必须保持地址和远端对象不变，输出排序 keys、rule IDs、SG ID 与精确地址合同。
5. VPC 由 grader 外建并通过变量注入，候选配置不得管理 VPC/subnet。
6. AWS provider 只允许 loopback root-origin LocalStack `ec2,sts` endpoints、字面量 `test/test` 和三项 skip flags。
7. grader 使用 Terraform 1.6.6 运行 7 个普通 plan tests；Full apply legacy fixture、交接同 lineage state、审计 saved-plan 的四个 `previous_address` 与零远端动作、验证真实规则、行重排 clean；随后从 LocalStack 删除 `admin` rule，要求 saved plan 只 create 对应稳定 key，修复后 destroy 并检查零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```
