# Challenge 32：把旧式安全组规则迁移到稳定的现代资源

这个练习从两个可运行的 `aws_security_group_rule` 实例开始。你会先证明 map key 能稳定
标识规则，再比较旧资源和 `aws_vpc_security_group_ingress_rule` 的 schema，审阅一次
明确的资源类型迁移，最后验证“独立规则资源与 inline rules 不混用”的边界。

## 官方考试目标

- **2c**：Compute and interpolate data using HCL functions
- **2d**：Use meta-arguments in configuration
- **1e**：Manage resource state and reconcile resource changes safely

使用官方 AWS 学习资源中的 `aws_security_group`、`aws_security_group_rule` 和
`aws_vpc_security_group_ingress_rule`。兼容 Terraform `>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-32
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 通过默认 Subnet 查询 VPC、创建 `tfpro-c32-rules` security group、类型化规则 map，以及两个
由 `for_each` 管理的旧式 ingress rule。没有 inline `ingress` block，也没有现代规则资源。

## Task 1：部署并记录旧式地址

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=legacy.tfplan'
terraform apply legacy.tfplan
Remove-Item -LiteralPath .\legacy.tfplan
terraform state list
terraform output starter_security_group
```

state 应包含以 `["web"]`、`["metrics"]` 为 key 的两个旧式规则实例。用 API 核验：

```powershell
$sgId = (terraform output -json starter_security_group | ConvertFrom-Json).id
aws --endpoint-url=http://localhost:4566 ec2 describe-security-group-rules `
  --filters "Name=group-id,Values=$sgId" `
  --query 'SecurityGroupRules[].{Protocol:IpProtocol,From:FromPort,To:ToPort,Cidr:CidrIpv4,Description:Description}'
```

## Task 2：证明稳定 Key 不依赖声明顺序

交换默认 map 中 `web` 与 `metrics` 的书写顺序，不改变 key 或 value。

```powershell
terraform fmt
terraform plan
```

预期 `No changes`。然后只修改 `metrics` 的 description：

```powershell
terraform plan
```

计划只能影响 `["metrics"]`，不能重建 `["web"]`。恢复原 description 并再次确认
`No changes`。

## Task 3：比较两种 Rule Schema

阅读 provider schema：

```powershell
terraform providers schema -json |
  Set-Content -LiteralPath .\provider-schema.json -Encoding utf8

$schema = Get-Content .\provider-schema.json -Raw | ConvertFrom-Json
$schema.provider_schemas.'registry.terraform.io/hashicorp/aws'.resource_schemas.aws_security_group_rule.block.attributes.PSObject.Properties.Name
$schema.provider_schemas.'registry.terraform.io/hashicorp/aws'.resource_schemas.aws_vpc_security_group_ingress_rule.block.attributes.PSObject.Properties.Name
```

记录两者在 CIDR、protocol 和 tags 上的差异，然后删除临时文件：

```powershell
Remove-Item -LiteralPath .\provider-schema.json
```

## Task 4：迁移到现代独立规则资源

用一个 `aws_vpc_security_group_ingress_rule` 加 `for_each` 替换旧资源。继续使用原 map
key，按现代 schema 映射 `cidr_ipv4`、`ip_protocol`、ports、description，并添加
`Challenge = "32"` tag。

```powershell
terraform fmt -check
terraform validate
terraform plan '-out=migration.tfplan'
terraform show migration.tfplan
```

由于 Terraform 资源类型和地址都发生变化，预期计划明确显示旧规则 destroy、现代规则
create；security group 本身不能重建。这个实验允许短暂替换规则，不宣称零停机。确认后：

```powershell
terraform apply migration.tfplan
Remove-Item -LiteralPath .\migration.tfplan
terraform state list
```

state 中不应再有 `aws_security_group_rule.legacy`。

## Task 5：扩展一条规则并守住“不混用”边界

只向 map 新增稳定 key `admin-ssh`，端口 22，CIDR 使用 `192.0.2.0/24`。

```powershell
terraform plan '-out=expand.tfplan'
terraform show expand.tfplan
terraform apply expand.tfplan
Remove-Item -LiteralPath .\expand.tfplan
terraform plan
```

预期只新增一个现代规则，最终 `No changes`。不要向 `aws_security_group.app` 添加 inline
`ingress`/`egress` block；同一安全组由 inline 与独立资源共同管理会造成所有权冲突和 drift。

## Task 6：发布合同、API 验收并清理

把输出整理为 `security_group_contract`，包含 group ID/name，以及按稳定 key 排序的规则。

```powershell
terraform output security_group_contract
$sgId = (terraform output -json security_group_contract | ConvertFrom-Json).id
aws --endpoint-url=http://localhost:4566 ec2 describe-security-group-rules `
  --filters "Name=group-id,Values=$sgId"
terraform state list
terraform plan
terraform destroy -auto-approve
```

API 应返回 3 条 ingress 规则；state 地址应使用三个稳定 key。销毁后 API 不应再返回该
security group。清除 Terraform 运行产物，目录最终只保留 `Readme.md` 与
`challenge-32.tf`。

## LocalStack 提醒

- LocalStack 可能简化 rule ID，但 protocol、ports、CIDR 和 description 可用于验收。
- 本题有意审阅一次类型迁移，不把 destroy/create 描述成无中断生产迁移。
- 不要把 default security group 的系统规则计入本题三条受管 ingress 规则。
