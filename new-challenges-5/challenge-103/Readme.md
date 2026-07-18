# Challenge 103：把复杂对象输入接到 Registry Security Group Module

本题 starter 已声明一份完整的 security group 业务合同，但还没有任何 module 或
托管资源。你会先补充输入不变量，再把复杂对象转换成 Registry module 所需的 inputs，
最后用 module outputs、Terraform state 与 LocalStack API 验收同一对象。

## 官方考试目标

- **2a**：Use language features to validate configuration
- **2b**：Query providers using data sources
- **2c / 2e**：转换复杂数据，并配置 input variables 与 outputs
- **4b**：调用 Registry module

参考 [Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
和 [Terraform 1.6 Module Sources](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)。
module 只创建白名单中的 `aws_security_group` 与 `aws_security_group_rule`。

## 开始之前

```powershell
Set-Location .\new-challenges-5\challenge-103
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

aws --endpoint-url=http://localhost:4566 ec2 describe-subnets `
  --filters Name=availability-zone,Values=us-east-1a
```

LocalStack Ultimate 必须运行；首次添加 module 时还需要访问 Terraform Registry。

## Starter 状态

Starter 包含：

- `security_group_contract`：包含 name、description、ingress object list 与 tags；
- 两条 ingress：HTTPS `443` 和管理端口 `8443`；
- 默认 `us-east-1a` subnet data source；
- `starter_input_contract` output；
- 没有 module，也没有 managed security group。

先阅读 object type 和默认值。不要把复杂变量拆成多个互不相关的标量变量。

## Task 1：证明 Starter 只有输入合同

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply -auto-approve
terraform output -json starter_input_contract
```

计划应显示 `0 to add, 0 to change, 0 to destroy`；apply 只把 data source 和 output 写入 state，
不会创建 managed resource。此后才能用 `terraform output` 读取 starter 合同。

使用 console 观察类型化结构：

```powershell
terraform console
```

```hcl
var.security_group_contract.name
var.security_group_contract.ingress[*].name
var.security_group_contract.ingress[*].from_port
```

## Task 2：给复杂合同添加可修复的 Validation

为 `security_group_contract` 添加 validation，至少保证：

- 每条规则的 from/to port 都在 `1..65535`；
- `from_port <= to_port`；
- ingress `name` 在列表中唯一。

运行一个端口顺序错误的失败用例：

用 PowerShell 对象生成 JSON，再通过 Terraform 标准的 `TF_VAR_` 环境变量注入复杂值，避免 Windows 原生命令行
转义先破坏内层引号：

```powershell
$invalidContract = @{
  name        = "tfpro-c103-application"
  description = "invalid contract"
  ingress = @(
    @{
      name        = "bad-range"
      from_port   = 9000
      to_port     = 8000
      protocol    = "tcp"
      cidr_block  = "10.103.0.0/16"
      description = "invalid range"
    }
  )
  tags = @{
    Challenge = "103"
    ManagedBy = "Terraform"
  }
} | ConvertTo-Json -Depth 4 -Compress

$env:TF_VAR_security_group_contract = $invalidContract
terraform plan
$validationExitCode = $LASTEXITCODE
Remove-Item Env:TF_VAR_security_group_contract
if ($validationExitCode -eq 0) { throw "Expected variable validation to fail" }
```

预期在创建任何资源前失败，错误信息应说明端口范围或顺序如何修复。环境变量已被立即清除；随后运行：

```powershell
terraform fmt
terraform validate
terraform plan
```

默认合同必须继续得到零资源计划。

## Task 3：把业务对象映射成 Registry Module Inputs

新增 module `application`：

- source 为 `terraform-aws-modules/security-group/aws`；
- version 精确固定为 `5.2.0`；
- name、description、tags 来自 `var.security_group_contract`；
- vpc_id 来自 `data.aws_subnet.selected.vpc_id`；
- `use_name_prefix = false`，保持精确名称 `tfpro-c103-application`；
- `egress_rules = ["all-all"]`。

`ingress_with_cidr_blocks` 必须使用 `for` expression 从每个业务 rule 生成 module
需要的 map，并映射：

- from/to port；
- `protocol`；
- `description`；
- 把单个 `cidr_block` 放到 module 字段 `cidr_blocks`。

不要在 module block 中重新手写 443 和 8443。

```powershell
terraform init
terraform fmt
terraform validate
terraform plan '-out=c103-module.tfplan'
terraform show .\c103-module.tfplan
```

计划应只在 `module.application` 下创建一个 SG 及其规则，不应修改输入默认值。

## Task 4：应用并检查 Module State

```powershell
terraform apply .\c103-module.tfplan
Remove-Item -LiteralPath .\c103-module.tfplan

terraform state list
terraform state show 'module.application.aws_security_group.this[0]'
```

因为 `use_name_prefix = false`，SG 地址应为
`module.application.aws_security_group.this[0]`。规则也必须位于
`module.application` 下；根模块不应出现独立 `aws_security_group`。

## Task 5：发布 Runtime Output，并用 API 验收

把 `starter_input_contract` 重构为 `security_group_runtime_contract`。最终 output
必须使用以下顶层 key：

- `id`：`module.application.security_group_id`；
- `name`：`module.application.security_group_name`；
- `vpc_id`：`module.application.security_group_vpc_id`；
- `ingress`：原始 ingress 业务合同；
- `ports_by_name`：用 `for` expression 生成的 `name => from_port` map；
- `runtime = "registry-module"`。

实际资源属性必须引用 module outputs，不能只回显变量。

```powershell
terraform apply -auto-approve
$contract = terraform output -json security_group_runtime_contract | ConvertFrom-Json
$contract

aws --endpoint-url=http://localhost:4566 ec2 describe-security-group-rules `
  --filters "Name=group-id,Values=$($contract.id)" `
  --query 'SecurityGroupRules[].{Egress:IsEgress,From:FromPort,To:ToPort,Protocol:IpProtocol,CIDR:CidrIpv4,Description:Description}'

terraform plan
```

API 必须包含 443/`10.103.0.0/16` 与 8443/`10.103.10.0/24`；最终 plan
必须 `No changes`。

## Task 6：State/API 双向验收并清理

```powershell
$contract = terraform output -json security_group_runtime_contract | ConvertFrom-Json
$securityGroupId = $contract.id

terraform state list
terraform output security_group_runtime_contract
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $securityGroupId
```

销毁后 state 应为空，API 应报告 SG not found。把 `challenge-103.tf` 恢复为 starter
内容，并删除运行产物：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能剩 `Readme.md` 与 `challenge-103.tf`。

## 易错点

- variable validation 负责调用者合同；不要把相同约束藏进 module resource。
- module output 表示实际资源，variable 表示请求；runtime 合同应清楚区分二者。
- `cidr_block` 是本题业务字段，`cidr_blocks` 是 module v5 的 input 字段。
