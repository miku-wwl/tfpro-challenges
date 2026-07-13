# Challenge 21：CSV 驱动的网络与安全规则工厂

**难度：95 / 100（Terraform Professional = 100）**  
**建议时间：100 分钟**

平台团队用复杂对象定义 VPC 与 subnets，用 CSV 管理不同环境的 ingress rules。你需要把弱类型 CSV 转成稳定、可验证的 Terraform resource graph。

完成 `starter/`：

1. 严格校验 `network`、`environment`、`rules_csv_path` 与 loopback endpoint。
2. 将 CSV 的端口、布尔值与字符串标准化成明确类型；只选择目标环境且 `enabled=true` 的行。
3. `aws_subnet.this`、`aws_security_group.this` 和 ingress rule 都必须使用业务 key；rule 必须以 `rule_id` 为 `for_each` key，绝不能使用 CSV 行号。
4. 用 `data.aws_vpc.managed` 与 `data.aws_subnet.managed` 回读真实网络，并由 subnet data source 的 CIDR 构造规则。
5. 用 `check` 验证 rule ID 唯一、subnet 引用有效、端口合法、同一 security group 的 owner 一致。
6. 输出稳定排序的 active IDs、resource addresses、owner 分组和 topology contract。
7. 将 `rules.csv` 换成 `rules-reordered.csv` 后必须是零变更 plan，输出与 state 地址完全一致。
8. 所有本题 AWS 资源都必须带 `RunId = var.run_id`；grader 用每次唯一值按 rule → SG → subnet → VPC 的依赖顺序做失败兜底清理。

grader 会在 LocalStack 中真实创建 1 个 VPC、3 个 subnet、3 个 security group 与 5 条 ingress rule，随后验证 CSV 重排、clean plan 和 destroy。除 4 个 canonical runs 外，还会实际执行负向 plan，验证 duplicate ID、非法协议/端口、owner 冲突、非法 network 与不存在的 CSV 路径都由预期的 check/validation 报告，而不是在 collection 构造阶段意外崩溃。

```powershell
pwsh ./tmp2/challenge-21/tests/grade.ps1
```

fixtures 是输入合同，不要编辑。禁止使用真实 AWS 凭证或非本机 endpoint。
