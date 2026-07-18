# Challenge 105：使用 `for_each` 创建稳定的 Registry Module 实例

一个 module block 不一定只代表一个 child module 实例。给 module 加上 `for_each` 后，每个 map key
都会进入 state address，成为 Terraform 跟踪对象身份的一部分。本题先应用 dev、prod 两个安全组，
再通过重排、扩容和输出合同验证 key 的稳定性。

## 官方考试目标

- **1b / 1c / 1e**：审阅计划、应用变更，并读取带 key 的 module/state address
- **2d**：在 module block 上使用 `for_each` meta-argument
- **2e**：使用复杂类型变量组织每个 module instance 的输入
- **4b**：调用并配置 Terraform Registry module

参考 [Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
和 [Terraform 1.6 Module Sources](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)。
module runtime 只使用考试范围内的 `aws_security_group` 与 `aws_security_group_rule`。

## 开始之前

```powershell
Set-Location .\new-challenges-5\challenge-105
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

aws --endpoint-url=http://localhost:4566 ec2 describe-subnets `
  --filters Name=availability-zone,Values=us-east-1a
```

要求 LocalStack Ultimate 正在运行，并允许 `terraform init` 访问 Registry。

## Starter 状态

`challenge-105.tf` 已包含：

- 一个 `map(object(...))` 变量，key 为 `dev` 与 `prod`；
- 默认 subnet data source；
- 一个使用 `for_each = var.environments` 的 Registry security-group module；
- 精确 module 版本 `5.2.0`。

starter 故意没有 root output。你将在验证实例身份后再发布输出合同。

## Task 1：应用 dev 与 prod 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c105-baseline.tfplan'
terraform show .\c105-baseline.tfplan
terraform apply .\c105-baseline.tfplan
Remove-Item -LiteralPath .\c105-baseline.tfplan
```

计划应创建两个安全组及各自的 ingress、egress 规则。module 实例不是数字下标，而是 map key：

```text
module.security_groups["dev"]
module.security_groups["prod"]
```

dev 必须允许 TCP 8080、`10.105.10.0/24`；prod 必须允许 TCP 443、
`10.105.20.0/24`。

## Task 2：追踪完整 State Address 与真实对象

```powershell
terraform state list
terraform state show 'module.security_groups[\"dev\"].aws_security_group.this[0]'
terraform state show 'module.security_groups[\"prod\"].aws_security_group.this[0]'

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --filters "Name=group-name,Values=tfpro-c105-dev,tfpro-c105-prod" `
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId}'
```

state 中每个地址都应以对应的 module key 开头。API 应恰好找到 `tfpro-c105-dev` 与
`tfpro-c105-prod`。资源的远端名称和 module key 都能帮助人阅读，但 Terraform 用完整 state
address 识别实例。

## Task 3：重排 Map，证明 Key 保持身份

只调整 `environments` 的书写顺序：把 `prod` block 移到 `dev` 前面，不得修改任何值。

```powershell
terraform fmt
terraform validate
terraform plan
```

预期 `No changes`。map 的书写顺序不会改变 `dev`、`prod` key，因此不应销毁或重建任何对象。
若出现替换，先检查是否误改了 key、name、port 或 CIDR，不要应用有破坏性的计划。

## Task 4：增加一个 Admin Module 实例

在 `environments` 中加入：

```hcl
admin = {
  name        = "tfpro-c105-admin"
  description = "Challenge 105 administration access"
  port        = 22
  cidr_block  = "10.105.30.0/24"
}
```

```powershell
terraform fmt
terraform validate
terraform plan '-out=c105-admin.tfplan'
terraform show .\c105-admin.tfplan
terraform apply .\c105-admin.tfplan
Remove-Item -LiteralPath .\c105-admin.tfplan
terraform state list
```

计划只能新增 `module.security_groups["admin"]` 下的安全组和规则；已有 dev、prod 不能改变。
应用后 state 中应同时存在三个 module key。

## Task 5：发布以 Key 为索引的输出合同

新增 output `security_group_contracts`。它必须用一个 `for` expression 返回 map，并让每个 key
对应以下字段：

- `id`：该 module 实例的 `security_group_id`；
- `name`：该 module 实例的 `security_group_name`；
- `vpc_id`：该 module 实例的 `security_group_vpc_id`；
- `port` 与 `cidr_block`：来自同一个 `var.environments` 元素。

不要按 dev、prod、admin 分别硬编码三个 output。

```powershell
terraform apply -auto-approve
$contracts = terraform output -json security_group_contracts | ConvertFrom-Json
$contracts.dev
$contracts.prod
$contracts.admin

$groupIds = @($contracts.dev.id, $contracts.prod.id, $contracts.admin.id) -join ','
aws --endpoint-url=http://localhost:4566 ec2 describe-security-group-rules `
  --filters "Name=group-id,Values=$groupIds" `
  --query 'SecurityGroupRules[].{Group:GroupId,Egress:IsEgress,From:FromPort,To:ToPort,CIDR:CidrIpv4}'

terraform plan
```

三个 output key 必须和三个 module key 一致；API 应能对应到 8080、443、22 三条 ingress 合同。
最终 plan 必须为 `No changes`。

## Task 6：验收、销毁并恢复 Starter

先保存 ID，再销毁：

```powershell
$contracts = terraform output -json security_group_contracts | ConvertFrom-Json
$groupIds = @($contracts.dev.id, $contracts.prod.id, $contracts.admin.id)

terraform state list
terraform destroy -auto-approve
terraform state list

foreach ($groupId in $groupIds) {
  aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
    --group-ids $groupId
}
```

state 应为空，每次 API 查询都应报告目标安全组不存在。然后把 `challenge-105.tf` 恢复为 starter：

- `environments` 只保留原始 dev、prod 内容和顺序；
- 保留原始 `for_each` module；
- 删除 `security_group_contracts` output；
- 不保留临时实验代码。

最后清理运行产物：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能剩 `Readme.md` 与 `challenge-105.tf`。

## 易错点

- `for_each` key 是实例身份；重命名 key 与重排 map 完全不同。
- Windows PowerShell 中含字符串 key 的 state address 要用单引号包住整个参数，并以 `\"` 保留内部双引号。
- 不要复制三份 module block；本题考查一个 module block 的多个稳定实例。
- output 的 map key 应从现有集合派生，不能和变量形成两份容易漂移的清单。
