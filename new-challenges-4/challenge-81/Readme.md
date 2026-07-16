# Challenge 81：把 AMI 与 Subnet 查询变成可执行的 EC2 合同

这个练习从一个只验证 LocalStack 身份的可运行 starter 开始。你不会把 AMI ID、Subnet ID
或 VPC ID写死在配置里，而是逐层查询它们、检查查询结果，再让一台 EC2 instance 消费
同一份类型化合同。重点不是“创建一台机器”，而是让 plan 能清楚说明每个选择来自哪里。

## 官方考试目标

- **2b**：Query providers using data sources
- **2c**：Compute and interpolate data using HCL functions
- **2e**：Configure input variables and outputs, including complex types
- 辅助使用 **1b / 1c**：生成、审阅并应用执行计划

使用官方 AWS 学习资源中的 `data.aws_ami`、`data.aws_subnet` 和 `aws_instance`。
本题固定兼容 Terraform `~> 1.6.0`，不要使用较新版本才有的功能。

## Starter 状态

工作目录：

```powershell
Set-Location .\new-challenges-4\challenge-81
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

目录中只有 `Readme.md` 和 `challenge-81.tf`。Starter 已经包含：

- AWS provider `5.80.0`，EC2 与 STS 指向 `http://localhost:4566`；
- 一个类型化的 `compute_spec`；
- caller identity 查询与 `starter_identity` 输出；
- **没有** AMI/Subnet data source，也没有 EC2 instance。

开始前确认 LocalStack 的 `ec2` 与 `sts` 服务正在运行。目录中不应有 `.terraform`、
lockfile、state 或 plan 文件。

## Task 1：运行最小身份基线

工作目录：`new-challenges-4/challenge-81`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply baseline.tfplan
terraform output starter_identity
```

预期成功，plan 只有 output 变化，没有资源 create。LocalStack account ID 通常为
`000000000000`。删除临时 plan：

```powershell
Remove-Item -LiteralPath .\baseline.tfplan
```

## Task 2：按合同查询唯一的最新 AMI

在 `challenge-81.tf` 中添加 `data "aws_ami" "selected"`：

1. 设置 `most_recent = true`，owner 为 `amazon`；
2. 用 `compute_spec.ami_name_pattern` 过滤 `name`；
3. 用合同过滤 `architecture`，并只接受 `available` 状态；
4. 添加临时输出，至少包含 AMI 的 `id`、`name` 和 `architecture`。

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve
terraform output selected_ami
```

预期成功，并选出一个 LocalStack 内置 AMI。不要把输出中的具体 AMI ID复制回配置。

验证失败路径时，临时覆盖查询模式：

```powershell
terraform plan '-var=compute_spec={ami_name_pattern=\"definitely-not-present-*\",architecture=\"x86_64\",availability_zone=\"us-east-1a\",instance_type=\"t3.micro\"}'
```

预期失败并报告找不到匹配 AMI；默认合同仍应保持有效。

## Task 3：查询指定可用区的默认 Subnet

添加 `data "aws_subnet" "selected"`，同时用以下 EC2 filters 限定结果：

- `availability-zone` 等于合同中的可用区；
- `default-for-az` 等于 `true`。

输出 Subnet 的 `id`、`vpc_id`、`cidr_block` 和 `availability_zone`。

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve
terraform output selected_subnet
```

预期只读查询成功，仍没有基础设施 create。若找不到默认 Subnet，先重启干净的
LocalStack；不要把运行时生成的 Subnet ID写死。

## Task 4：让 EC2 消费两个查询结果

创建 `aws_instance.exercise`：

- `ami` 来自 `data.aws_ami.selected.id`；
- `subnet_id` 来自 `data.aws_subnet.selected.id`；
- `instance_type` 来自 `compute_spec`；
- tags 至少含 `Name = "tfpro-c81-query-contract"` 与 `Challenge = "81"`。

先保存并审阅计划，再应用同一份计划：

```powershell
terraform plan '-out=ec2.tfplan'
terraform show ec2.tfplan
terraform apply ec2.tfplan
Remove-Item -LiteralPath .\ec2.tfplan
```

预期只创建 1 台 LocalStack EC2 instance。LocalStack 不会启动真实虚拟机，本题验证的
是 AWS API 对象和 Terraform state，而不是 SSH 或操作系统启动过程。

## Task 5：发布一个可审计的 Compute Contract

把临时输出整理为最终 `compute_contract`，至少包含：

- instance ID、instance type；
- AMI ID 与 AMI name；
- Subnet ID、VPC ID、CIDR 和可用区；
- caller account ID。

输出结构应直接引用资源和 data source，而不是复制字符串。

```powershell
terraform fmt -check
terraform validate
terraform plan
terraform apply -auto-approve
terraform output compute_contract
terraform state list
terraform state show aws_instance.exercise
```

第二次 `terraform plan` 必须显示 `No changes`。

## Task 6：从 State 与 API 双向验收并清理

```powershell
$instanceId = terraform output -json compute_contract |
  ConvertFrom-Json |
  Select-Object -ExpandProperty instance_id

aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $instanceId `
  --query 'Reservations[].Instances[].{Id:InstanceId,Image:ImageId,Subnet:SubnetId,Type:InstanceType}'

terraform plan
terraform destroy -auto-approve
```

API 返回的 Image、Subnet 与 Type 应和 `compute_contract` 一致。销毁后再运行：

```powershell
terraform state list
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $instanceId
```

Terraform state 应为空；API 查询应不再返回运行中的目标实例。最后删除运行产物，使目录
恢复为最初的两个源文件。

## LocalStack 提醒

- LocalStack 预置 AMI catalog 会随版本变化，所以依赖过滤条件，不依赖某个固定 AMI ID。
- 默认 VPC/Subnet 是模拟对象；若其他练习删除了它们，重启 LocalStack 后再做本题。
- LocalStack EC2 不运行真实 guest，不能用 user-data 执行结果或 SSH 作为验收条件。
