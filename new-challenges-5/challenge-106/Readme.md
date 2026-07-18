# Challenge 106：把 Provider Alias 显式映射给 Registry Module

child module 默认继承未命名的 provider configuration；alias 不会自动继承。本题从“data source
使用 alias、module 使用 default”的可运行基线开始，先制造只有 alias 时的失败，再用 module
`providers` map 明确连接关系，最后让两个 module 分别使用两个 alias。

## 官方考试目标

- **1a**：初始化 provider 与 remote child modules
- **1e**：解释 provider configuration、module address 与 state 的关系
- **4b**：调用 Registry child module
- **5b**：配置 provider alias、排查隐式 default configuration，并向 child module 显式传递 provider

参考 [Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
和 [Terraform 1.6 Module Sources](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)。
module runtime 只使用考试范围内的 `aws_security_group` 与 `aws_security_group_rule`。

## 开始之前

```powershell
Set-Location .\new-challenges-5\challenge-106
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

aws --endpoint-url=http://localhost:4566 ec2 describe-subnets `
  --filters Name=availability-zone,Values=us-east-1a
```

要求 LocalStack Ultimate 正在运行，并允许 `terraform init` 访问 Registry。

## Starter 状态

`challenge-106.tf` 包含两个 AWS provider configuration：

- 未命名的 default provider；
- alias 为 `primary` 的 provider。

subnet data source 显式使用 `aws.primary`，而 `module.application` 没有 `providers` map，所以它继承
default provider。两者当前都指向同一个 LocalStack endpoint，结果可运行，但连接方式不同。

## Task 1：建立 Default 与 Alias 混用的基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform providers
terraform plan '-out=c106-baseline.tfplan'
terraform show .\c106-baseline.tfplan
terraform apply .\c106-baseline.tfplan
Remove-Item -LiteralPath .\c106-baseline.tfplan

terraform output -json starter_provider_contract
terraform state list
```

计划应创建 `tfpro-c106-application` 安全组以及 HTTPS ingress、egress。output 中
`module_provider` 为 `default`。这段文字是 starter 对连接关系的显式合同，不是 Terraform 自动返回的
provider alias。

## Task 2：移除 Default，观察隐式配置失败

删除未命名的 `provider "aws"` block，只保留 `provider "aws" { alias = "primary" ... }`；暂时不要给
module 添加 `providers` map。

为避免环境中原有 region 掩盖问题，先保存它并设置一个明确无效的 guard value：

```powershell
$previousDefaultRegion = $env:AWS_DEFAULT_REGION
$env:AWS_DEFAULT_REGION = "not-a-region"

terraform fmt
terraform validate
terraform plan
```

预期 plan 在访问 AWS 前因未命名 provider 的 region/configuration 无效而失败。原因是：当所有显式
AWS provider block 都带 alias，但某个 resource 或 child module 仍请求默认 `aws` 时，Terraform 会尝试
使用一个隐式的空 default configuration。alias `primary` 不会自动代替它。

不要应用这一步，也不要通过加入另一个真实 endpoint 来绕过失败。

## Task 3：把 `aws.primary` 显式传给 Module

在 `module.application` 中加入：

```hcl
providers = {
  aws = aws.primary
}
```

然后验证。无论成功或失败，都在检查后恢复原环境变量：

```powershell
terraform fmt
terraform validate
terraform plan

if ([string]::IsNullOrEmpty($previousDefaultRegion)) {
  Remove-Item Env:AWS_DEFAULT_REGION -ErrorAction SilentlyContinue
} else {
  $env:AWS_DEFAULT_REGION = $previousDefaultRegion
}
```

现在 plan 应为 `No changes`：同一个远端对象仍由 `module.application` 管理，只是 module 的 provider
configuration 连接变得显式。`starter_provider_contract.module_provider` 仍是静态 starter 字符串，下一步
完成两个 alias 后再把它替换成准确的 runtime contract。

## Task 4：增加 Secondary Alias 与第二个 Module

新增完整的 `provider "aws"` block，要求：

- `alias = "secondary"`；
- region、测试凭据、skip 参数以及 EC2/STS endpoints 与 `primary` 一致。

再新增 `module.admin`，source 为 `terraform-aws-modules/security-group/aws`，精确
`version = "5.2.0"`，并显式映射：

```hcl
providers = {
  aws = aws.secondary
}
```

admin module 合同：

- name `tfpro-c106-admin`，关闭 name prefix；
- VPC ID 引用 starter subnet data source；
- TCP 22 ingress，CIDR `10.106.10.0/24`；
- `egress_rules = ["all-all"]`；
- tags 包含 Challenge 106、Role Admin、ManagedBy Terraform。

```powershell
terraform init
terraform fmt
terraform validate
terraform plan '-out=c106-admin.tfplan'
terraform show .\c106-admin.tfplan
terraform apply .\c106-admin.tfplan
Remove-Item -LiteralPath .\c106-admin.tfplan
```

计划只能新增 admin 安全组及规则；application 不应重建。

## Task 5：检查 Provider Tree、State 与 API

删除 `starter_provider_contract`，新增 `provider_runtime_contract`，必须使用以下结构：

- `application.id`、`application.name` 来自 application module outputs，另有
  `application.provider_alias = "primary"`；
- `admin.id`、`admin.name` 来自 admin module outputs，另有
  `admin.provider_alias = "secondary"`；
- 顶层 `vpc_id` 来自 starter subnet data source。

alias 字符串是你发布的合同；Terraform 不提供一个表达式来从 module 反射其 provider alias。

```powershell
terraform apply -auto-approve
terraform providers
terraform state list

$contract = terraform output -json provider_runtime_contract | ConvertFrom-Json
$contract

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $contract.application.id $contract.admin.id `
  --query 'SecurityGroups[].{Id:GroupId,Name:GroupName,Vpc:VpcId}'

terraform plan
```

`terraform providers` 应显示两个 module 都需要 `registry.terraform.io/hashicorp/aws`；root configuration
决定它们实际连接到哪个 alias。state address 仍是 `module.application...` 与 `module.admin...`，不会把
`primary` 或 `secondary` 写入 module address。API 必须返回两个精确名称，最终 plan 必须为
`No changes`。

## Task 6：验收、销毁并恢复 Starter

```powershell
$contract = terraform output -json provider_runtime_contract | ConvertFrom-Json
$applicationId = $contract.application.id
$adminId = $contract.admin.id

terraform state list
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $applicationId $adminId
```

state 应为空，API 应报告目标安全组不存在。然后把 `challenge-106.tf` 恢复到 starter：

- 恢复未命名 default provider 与 `aws.primary`；
- 删除 `aws.secondary`；
- `module.application` 恢复为没有 `providers` map；
- 删除 `module.admin` 和 runtime output；
- 恢复原始 `starter_provider_contract`。

最后清理运行产物：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能剩 `Readme.md` 与 `challenge-106.tf`。

## 易错点

- alias 不会自动成为 default，也不会自动传给 child module。
- module `providers` map 左侧是 child module 期望的本地 provider 名，右侧是 root 的 configuration。
- 更改 module 的 provider 映射不会改变它的 state address。
- 本题所有 provider endpoints 都必须保持为 LocalStack；不要把失败实验指向真实 AWS。
