# Challenge 15：CSV 驱动的网络与安全规则工厂

难度：**89 / 100**　建议用时：**75 分钟**

## 场景

平台团队从 CMDB 导出安全规则。你需要查询既有 VPC 与子网，把 CSV 转换为稳定的 Security Group 和独立 ingress/egress rule 资源。CSV 会被重新排序，也会同时包含其他环境、停用规则和不同 owner；一次无意义的行顺序变化不能导致资源换地址。

本题默认连接本机 LocalStack；canonical tests 仍使用 AWS mock provider快速验证输出，
完成题目后可在 LocalStack 中执行真实 plan/apply/destroy。

## 开始

```powershell
cd tmp2/challenge-15/starter
terraform init
pwsh ../tests/grade.ps1 -Root .
```

只修改 `starter/`。`fixtures/` 是输入合同，不要通过修改 fixture 让测试通过。

## 任务

1. 完成 `target_environment` validation，只允许 `dev`、`staging`、`prod`。
2. 使用 `data.aws_vpc.selected` 按 `Name` tag 查询 VPC；使用一个带 `for_each` 的 `data.aws_subnet.selected` 按 tier 查询所需子网。
3. `csvdecode` 后显式转换端口和布尔值；只保留目标环境且 `enabled=true` 的规则。
4. 每个活跃 service 只创建一个 `aws_security_group.workload`。
5. 分别使用一个 ingress 和一个 egress resource block 创建规则。`office`、`partners` 来自变量映射，`vpc` 必须解析为查询到的 VPC CIDR，合法 CIDR 可直接使用。
6. `for_each` key 必须由规则业务身份组成，不能使用行号。调换 CSV 行顺序后，地址集合必须不变。
7. 输出排序后的 service、ingress/egress key、按 owner 分组的 key，以及 subnet ID 映射。

## 验收

```powershell
terraform fmt -check -recursive .
terraform validate
pwsh ../tests/grade.ps1 -Root .
```

测试会验证默认输入、重排输入、mock data source 结果，以及非法环境 validation。

## 不变量

- CSV 行顺序不属于资源身份。
- `dev` 和停用规则不会出现在 `prod` plan。
- SG 与 rule 使用查询得到的 VPC，不硬编码 VPC/subnet ID。
- 相同 owner 下的 key 排序固定，所有输出可供下游自动化消费。

## 安全边界

- provider 只使用固定 `test/test` 凭证，EC2/STS endpoint 必须指向 loopback LocalStack。
- 不要把 endpoint 改成真实 AWS；`test/test` 不是生产凭证方案。
- 不修改 fixtures 来迁就实现。

## Terraform Professional objective

覆盖 Professional 大纲中的复杂 HCL authoring、data source 查询、collection transformation、`for_each` 资源身份、输入验证、provider schema 推理，以及可预测 plan 的生产级设计。
