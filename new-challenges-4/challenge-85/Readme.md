# Challenge 85：从 HCL Network Matrix 编译独立 Ingress Rules

人类通常按“web 可以从哪些网段访问哪些端口”描述网络策略；AWS API最终需要一条条具体
规则。这个练习用 `setproduct` 和 `flatten` 把 policy matrix 编译成稳定 map，再由一个
`aws_vpc_security_group_ingress_rule` block 创建全部规则。

## 官方考试目标

- **2a**：Use language features to validate configuration
- **2c**：Compute and interpolate data using HCL functions
- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types
- 辅助使用 **2b**：用 Subnet data source 查询现有 VPC

使用官方 AWS 学习资源中的 `data.aws_subnet`、`aws_security_group` 与
`aws_vpc_security_group_ingress_rule`。本题固定 Terraform `~> 1.6.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-4\challenge-85
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 已经包含：

- 一个 typed `network_matrix`：web 产生 4 个组合，admin 产生 1 个组合；
- 默认 Subnet 查询，用它得到 VPC ID；
- 一个只有 egress、尚无 ingress 的 Security Group；
- 没有 locals，也没有 standalone ingress rule resource。

不要在 `aws_security_group.application` 中加入 inline ingress；本题让 standalone resource
成为 ingress 的唯一 owner，避免两种管理方式互相覆盖。

## Task 1：部署空 Ingress 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply baseline.tfplan
terraform output starter_security_group
Remove-Item -LiteralPath .\baseline.tfplan
```

预期创建 1 个 Security Group，没有 Terraform 管理的 ingress rules。

```powershell
$sgId = (terraform output -json starter_security_group | ConvertFrom-Json).id
aws --endpoint-url=http://localhost:4566 ec2 describe-security-group-rules `
  --filters Name=group-id,Values=$sgId
```

LocalStack 可能展示默认 egress，但不应出现 80、443 或 22 ingress。

## Task 2：在展开之前验证 Matrix

给 `network_matrix` 添加 validation：

1. `network_matrix` map 不为空；
2. `network_matrix` 中的每个 policy（map value）至少有一个 CIDR 与一个 port；
3. 每个 port 在 1～65535；
4. 每个 CIDR 能通过 `can(cidrnetmask(...))`；
5. protocol 只允许 `tcp` 或 `udp`。

```powershell
terraform fmt
terraform validate
terraform plan
```

正常路径应为 `No changes`。验证失败路径：

```powershell
terraform plan '-var=network_matrix={bad={cidrs=[\"10.0.0.0/24\"],ports=[0],protocol=\"tcp\",description=\"invalid\"}}'
```

预期在 variable validation 阶段失败，不会创建远端规则。

## Task 3：把 Policy 展开成 Canonical Rows

添加 locals：

1. 对每个 policy 使用 `setproduct(policy.cidrs, policy.ports)`；
2. 用 `flatten` 得到 rows；每行包含 policy、CIDR、port、protocol 与 description；
3. 为每行生成完全由已知输入组成的 key，例如
   `web|10.20.0.0/24|443|tcp`；
4. 把 rows 转成 `local.ingress_by_key` map。

使用 `terraform console` 直接检查 locals，不需要添加临时 output：

```powershell
terraform console
```

```hcl
length(local.ingress_by_key)
sort(keys(local.ingress_by_key))
local.ingress_by_key
```

预期长度为 `5`，并能看到 5 个 canonical rows。退出 console 后运行
`terraform plan`，预期为 `No changes`。

> **Note（☆）— `setproduct`**：生成多个集合的所有组合。本题中
> `setproduct(policy.cidrs, policy.ports)` 返回 `[CIDR, port]` 对；例如 2 个
> CIDR × 2 个 port 会得到 4 组，使用 `pair[0]` 取 CIDR、`pair[1]` 取 port。
>
> 可复用模板：
>
> ```hcl
> flatten([
>   for name, item in var.items : [
>     for pair in setproduct(item.set_a, item.set_b) : {
>       name = name
>       a    = pair[0]
>       b    = pair[1]
>     }
>   ]
> ])
> ```

## Task 4：用一个 Resource Block 创建五条规则

添加 `aws_vpc_security_group_ingress_rule.matrix`：

- `for_each = local.ingress_by_key`；
- `security_group_id` 引用 starter Security Group；
- `cidr_ipv4`、`from_port`、`to_port`、`ip_protocol` 和 description 均来自 row；
- 每条规则的 from/to port 相同。

```powershell
terraform plan '-out=rules.tfplan'
terraform show rules.tfplan
terraform apply rules.tfplan
Remove-Item -LiteralPath .\rules.tfplan
terraform state list
```

预期精确创建 5 个 ingress rule instances，地址使用稳定的业务 key，而不是数字 index。

## Task 5：证明集合重排不扰动地址

先只改变 `cidrs` 与 `ports` 在源码中的书写顺序：

```powershell
terraform plan
```

预期 `No changes`。然后给 admin policy 增加 port `3389`：

```powershell
terraform plan '-out=expand.tfplan'
terraform show expand.tfplan
terraform apply expand.tfplan
Remove-Item -LiteralPath .\expand.tfplan
```

预期只新增一条 `admin|203.0.113.10/32|3389|tcp`，现有五条规则不替换。

## Task 6：发布规则合同、API 验收与清理

将输出整理为 `ingress_contract`：包含 Security Group/VPC ID，以及按 stable key 排序的
规则对象列表。

```powershell
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output ingress_contract

$sgId = (terraform output -json ingress_contract | ConvertFrom-Json).security_group_id
aws --endpoint-url=http://localhost:4566 ec2 describe-security-group-rules `
  --region us-east-1 `
  --filters Name=group-id,Values=$sgId `
  --query 'SecurityGroupRules[?IsEgress==`false`].{Id:SecurityGroupRuleId,Cidr:CidrIpv4,From:FromPort,To:ToPort,Protocol:IpProtocol,Description:Description}'

terraform plan
terraform destroy -auto-approve
```

完成态应有 6 条 ingress；最终 plan 必须 `No changes`。销毁后 API 不应再找到该 group，
并清理所有运行产物，只保留 README 与 `.tf`。

## LocalStack 提醒

- LocalStack 的默认 egress rule 可能出现在 API 输出中，因此验收时过滤
  `IsEgress == false`。
- 不要混用 inline `ingress {}`、`aws_security_group_rule` 和本题的
  `aws_vpc_security_group_ingress_rule` 管理同一方向，否则会产生所有权冲突。
- stable key 可以包含 `/`、`.` 与 `|`；Terraform resource address 会正确引用带引号的
  map key。
