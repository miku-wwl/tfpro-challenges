# Challenge 118：Git module 的 `for_each`、实例地址与定向计划

module block 也可以使用 `for_each`。一旦这样做，module 不再只有一个地址，而是形成由稳定 key 标识的
module instances。本题用 Git module 创建 dev/prod 两个 LocalStack security groups：先读懂完整 state 地址，
再只修改 prod 并生成定向保存计划，最后增加 qa 实例并证明 map 的书写顺序不会改变对象身份。

## 官方考试目标

- **1b / 1c**：生成、审阅并应用执行计划，包括谨慎使用资源定向
- **1e**：理解配置、module instance address、state 与远端对象的关系
- **2d**：使用 `for_each` meta-argument
- **4b**：在配置中调用远程 module

考纲依据为 [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)，
source 语法依据 Terraform 1.6 的
[module sources](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)。本题使用 module 与
`for_each` 语义。远程 Git module 内只管理考试资源清单内的
`aws_security_group` 和 `aws_security_group_rule`；默认 VPC 通过 `data.aws_subnet` 查询。AWS API 指向
LocalStack Ultimate。

## Starter 状态

```powershell
Set-Location .\new-challenges-5\challenge-118
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

git --version
aws --endpoint-url=http://localhost:4566 sts get-caller-identity
```

目录只有 `Readme.md` 与 `challenge-118.tf`。Starter 已用 Git tag `v5.2.0` 固定 module，并定义：

| key | CIDR | TCP port | security group |
|---|---|---:|---|
| `dev` | `10.118.10.0/24` | 8080 | `tfpro-c118-dev` |
| `prod` | `10.118.20.0/24` | 8443 | `tfpro-c118-prod` |

`for_each = local.services` 使这些 key 成为 state identity 的一部分。

## Task 1：部署两个 module instances

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c118-baseline.tfplan'
terraform show .\c118-baseline.tfplan
terraform apply .\c118-baseline.tfplan
Remove-Item -LiteralPath .\c118-baseline.tfplan

terraform output service_contracts
terraform state list
terraform plan
```

应创建两个 security groups 及各自的一条 ingress rule。state 地址应明确包含
`module.service["dev"]` 和 `module.service["prod"]`，而不是依赖 map 的行号。最后 plan 为
`No changes`。

## Task 2：用完整 module instance 地址查询

PowerShell 调用原生命令时，带字符串 key 的 Terraform 地址要保留内部双引号：

```powershell
terraform state list 'module.service[\"dev\"]'
terraform state list 'module.service[\"prod\"]'
terraform state show 'module.service[\"prod\"].aws_security_group.this[0]'

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --filters Name=tag:Challenge,Values=118 `
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Environment:Tags[?Key==`Environment`]|[0].Value,Ingress:IpPermissions}'
```

确认两个 module instances 的 group ID 不同，tag 与端口分别匹配 dev/prod。module instance 是
`module.service["prod"]`；其内部 resource 是更深一层地址，二者不要混淆。

## Task 3：只修改 prod，并审阅定向保存计划

只把 `local.services.prod.port` 从 `8443` 改为 `9443`，其他 key 和 inputs 保持不变。先查看完整计划：

```powershell
terraform plan
```

完整计划只能涉及 prod module instance 内的 ingress rule。然后生成一个以整个 prod module instance 为范围的
保存计划：

```powershell
terraform plan '-target=module.service[\"prod\"]' '-out=c118-prod.tfplan'
terraform show .\c118-prod.tfplan
terraform apply .\c118-prod.tfplan
Remove-Item -LiteralPath .\c118-prod.tfplan
terraform plan
```

应用后完整 plan 必须为 `No changes`，API 中 prod 端口应为 9443，dev 仍为 8080。`-target` 是异常恢复或
明确局部操作工具，不是日常跳过完整依赖图审阅的方式；因此本题在 apply 前后都要求运行完整 plan。

## Task 4：用新 key 增加 qa module instance

在 `local.services` 中增加：

```hcl
qa = {
  cidr = "10.118.30.0/24"
  port = 9000
}
```

```powershell
terraform fmt
terraform validate
terraform plan '-out=c118-qa.tfplan'
terraform show .\c118-qa.tfplan
```

计划应只创建 `module.service["qa"]` 内的 security group 和 ingress rule；不能替换 dev/prod。确认后：

```powershell
terraform apply .\c118-qa.tfplan
Remove-Item -LiteralPath .\c118-qa.tfplan
terraform output service_contracts
terraform state list 'module.service[\"qa\"]'
```

## Task 5：重排 map，证明 key 而不是顺序维持身份

仅调整 `local.services` 三个条目的书写顺序，例如改成 qa、prod、dev；值完全不变。然后运行：

```powershell
terraform fmt
terraform validate
terraform plan '-out=c118-reorder.tfplan'
terraform show .\c118-reorder.tfplan
```

必须严格 `No changes`。`for_each` 实例由字符串 key 标识，map 的展示顺序不构成 state identity。删除空计划并
进行最终验收：

```powershell
Remove-Item -LiteralPath .\c118-reorder.tfplan
terraform state list

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --filters Name=tag:Challenge,Values=118 `
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Environment:Tags[?Key==`Environment`]|[0].Value,Ingress:IpPermissions}'
```

API 应显示三个固定名称，state 应显示三个稳定 module keys。

## Task 6：销毁并恢复两实例 starter

先在包含 qa、prod 9443 的当前配置下销毁所有实例：

```powershell
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --filters Name=tag:Challenge,Values=118 `
  --query 'SecurityGroups'
```

state 和 API 目标结果都应为空。然后删除 qa、把 prod port 恢复为 8443，并恢复 starter 中 dev/prod 的原始
书写顺序。最后删除运行产物：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

目录只能保留 `Readme.md` 和 starter `challenge-118.tf`。

## 边界提醒

- `for_each` key 是 module instance identity；修改 key 等价于旧实例消失、新实例出现，除非显式迁移 state。
- 定向计划仍可能包含依赖项，而且 Terraform 会给出 incomplete-plan 警告；最终必须审阅完整 plan。
- source 中的 tag 固定 module 发行版；`.terraform.lock.hcl` 不锁 Git module。
- 本题不加入并发脚本、评分器或批量 AWS 清理工具。
