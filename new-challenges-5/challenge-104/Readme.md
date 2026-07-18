# Challenge 104：调用 Registry Package 中的 `//modules/http-80` 子模块

Registry source 地址可以选择整个 package，也可以用双斜杠进入其中的子目录。本题从
provider 与 subnet data source 开始，调用预配置 HTTP 规则的 `http-80` submodule，
再从嵌套 state 地址和 LocalStack API 证明 module 层级。

## 官方考试目标

- **1a**：初始化并安装 remote child modules
- **1e**：理解嵌套 module 的 state address
- **2b**：使用 data source 查询 provider
- **4b**：使用 Registry module 与 package subdirectory source

参考 [Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
和 [Terraform 1.6 Module Sources](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)。
module runtime 只使用 `aws_security_group` 与 `aws_security_group_rule`。

## 开始之前

```powershell
Set-Location .\new-challenges-5\challenge-104
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

aws --endpoint-url=http://localhost:4566 ec2 describe-subnets `
  --filters Name=availability-zone,Values=us-east-1a
```

要求 LocalStack Ultimate 运行，并允许 `terraform init` 访问 Registry。

## Starter 状态

`challenge-104.tf` 只有 provider、默认 subnet data source 和
`starter_network_contract` output；没有 module 或 managed resource。

依赖链目标是：

```text
root module
  └─ module.http
       └─ module.sg
            ├─ aws_security_group
            └─ aws_security_group_rule
```

## Task 1：验证无资源网络基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply -auto-approve
terraform output starter_network_contract
```

预期 `0 to add, 0 to change, 0 to destroy`；apply 只把 data source 和 output 写入 state，
不会创建 managed resource。output 中 subnet 属于 `us-east-1a` 并提供一个 VPC ID。

## Task 2：添加 `http-80` Submodule

新增 module `http`，必须使用：

```text
terraform-aws-modules/security-group/aws//modules/http-80
```

并精确固定 `version = "5.2.0"`。配置：

- name `tfpro-c104-http`；
- description `Challenge 104 HTTP access`；
- vpc_id 引用 starter data source；
- `use_name_prefix = false`；
- `ingress_cidr_blocks = ["10.104.0.0/16"]`；
- tags 包含 Challenge 104 与 ManagedBy Terraform。

不要自行声明端口 80 的 custom rule；该规则正是 submodule 的预配置行为。

```powershell
terraform init
terraform fmt
terraform validate
```

init 应下载 package `terraform-aws-modules/security-group/aws 5.2.0`，并从其中选择
`modules/http-80`。

## Task 3：检查 Package Source 与嵌套 Module Tree

```powershell
$modules = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$modules.Modules |
  Where-Object { $_.Key -like "http*" } |
  Select-Object Key,Source,Version,Dir

terraform providers
```

预期至少看到：

- key `http`，source 带 `//modules/http-80`、version 为 `5.2.0`；
- 该 submodule 内部调用的嵌套 module `http.sg`。

双斜杠之前是 Registry package 地址，之后是 package 内的目录；它不是 URL 中重复输入的
普通斜杠，也不能改成单斜杠。

## Task 4：应用并验证完整 State Address

```powershell
terraform plan '-out=c104-http.tfplan'
terraform show .\c104-http.tfplan
terraform apply .\c104-http.tfplan
Remove-Item -LiteralPath .\c104-http.tfplan

terraform state list
terraform state show 'module.http.module.sg.aws_security_group.this[0]'
```

计划应创建 4 个 managed resources：一个 SG、CIDR HTTP ingress、self ingress 和 egress。因为关闭
name prefix，SG 的完整地址应是：

```text
module.http.module.sg.aws_security_group.this[0]
```

这说明 state address 记录调用层级，而不是只记录远端资源名。

## Task 5：发布 Submodule 合同并查询 API

新增 `http_runtime_contract` output，使用以下明确的顶层 key：

- `id = module.http.security_group_id`；
- `name = module.http.security_group_name`；
- `vpc_id = module.http.security_group_vpc_id`；
- `source = "terraform-aws-modules/security-group/aws//modules/http-80"`；
- `version_constraint = "5.2.0"`；
- `expected_port = 80`。

```powershell
terraform apply -auto-approve
$contract = terraform output -json http_runtime_contract | ConvertFrom-Json
$contract

aws --endpoint-url=http://localhost:4566 ec2 describe-security-group-rules `
  --filters "Name=group-id,Values=$($contract.id)" `
  --query 'SecurityGroupRules[].{Egress:IsEgress,From:FromPort,To:ToPort,Protocol:IpProtocol,CIDR:CidrIpv4}'

terraform plan
```

API 中必须存在 TCP 80、CIDR `10.104.0.0/16` 的 ingress，并保留 module 的 self ingress；最终 plan
必须 `No changes`。

## Task 6：验收、销毁并恢复 Starter

```powershell
$contract = terraform output -json http_runtime_contract | ConvertFrom-Json
$securityGroupId = $contract.id

terraform state list
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $securityGroupId
```

state 应为空，API 应报告 not found。把 `challenge-104.tf` 恢复到只有 provider、
data source 和 starter output 的初始状态，然后清理：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能剩 `Readme.md` 与 `challenge-104.tf`。

## 易错点

- Registry module 的 `version` 属于整个 package，也约束所选 submodule。
- `module.http` 是你的调用地址；`module.http.module.sg` 是包内嵌套调用。
- 不要复制 module cache 中的文件到 challenge，也不要手工编辑它们。
