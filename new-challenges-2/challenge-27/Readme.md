# Challenge 27：把 AMI、Subnet 与账号查询收敛成 EC2 合同

计算平台不允许把运行时 ID复制进代码。你需要从一个只读取账号身份的 starter 开始，按输入
合同查询 AMI 和默认 Subnet，先审阅查询结果，再让 EC2 instance 消费同一份数据。最终输出
必须能解释 instance 的每个关键选择来自哪里。

## 官方考试目标

- **2b**：Query providers using data sources
- **2c**：Compute and interpolate data using HCL functions
- **2e**：Configure input variables and outputs, including complex types
- 辅助使用 **1b / 1c**：保存、审阅并应用执行计划

本题只使用官方 AWS 学习资源中的 `data.aws_ami`、`data.aws_subnet`、
`data.aws_caller_identity` 和 `aws_instance`。配置兼容 Terraform
`>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-27
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

目录中只有 `Readme.md` 和 `challenge-27.tf`。Starter 包含 AWS provider `5.80.0`、类型化
`compute_request`、caller identity 和 `starter_identity` 输出；它**没有** AMI/Subnet 查询，
也没有 EC2 instance。

开始前确认 LocalStack 的 EC2 与 STS 服务已运行，并保留默认 VPC、默认 Subnet 和内置 AMI。

## Task 1：执行只读身份基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=identity.tfplan'
terraform apply .\identity.tfplan
Remove-Item -LiteralPath .\identity.tfplan
terraform output -json starter_identity | ConvertFrom-Json
```

计划不应创建 managed resource；账号通常是 `000000000000`。这是后续 compute contract 的
账号来源，不要把输出复制成 local 常量。

## Task 2：按输入合同查询唯一 AMI

添加 `data "aws_ami" "selected"`，满足以下合同：

- `most_recent = true`，owners 只包含 `amazon`；
- 用 `compute_request.ami_name_pattern` 过滤 `name`；
- 用输入合同过滤 `architecture`；
- 只接受 `available` 状态。

添加临时 `selected_ami` 输出，包含 id、name、architecture。然后执行：

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve
terraform output -json selected_ami | ConvertFrom-Json
```

应选出一个 LocalStack 内置 AMI，且仍不创建基础设施。验证失败路径：

```powershell
terraform plan '-var=compute_request={ami_name_pattern=\"definitely-not-present-*\",architecture=\"x86_64\",availability_zone=\"us-east-1a\",instance_type=\"t3.micro\"}'
```

预期报告找不到匹配 AMI。不要把成功查询得到的具体 AMI ID写回配置。

## Task 3：查询指定可用区的默认 Subnet

添加 `data "aws_subnet" "selected"`，使用 EC2 filter 名称：

- `availability-zone` 等于输入合同的 availability zone；
- `default-for-az` 等于字符串 `true`。

添加临时 `selected_subnet` 输出，包含 id、vpc_id、cidr_block 和 availability_zone。

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve
$subnet = terraform output -json selected_subnet | ConvertFrom-Json
$subnet
aws --endpoint-url=http://localhost:4566 ec2 describe-subnets `
  --subnet-ids $subnet.id `
  --query 'Subnets[].{Id:SubnetId,Vpc:VpcId,Cidr:CidrBlock,Az:AvailabilityZone}'
```

Terraform 输出与 API 应一致，且可用区为 `us-east-1a`。找不到默认 Subnet 时应恢复干净的
LocalStack 默认网络，而不是写死另一个 ID。

## Task 4：组合合同并让 EC2 消费它

用 local value 组合一份 `selected_compute`，至少包含：

- AMI 的 id、name、architecture；
- Subnet 的 id、VPC、CIDR、availability zone；
- 输入的 instance type；
- caller account ID。

创建 `aws_instance.exercise`，其 ami、subnet_id 和 instance_type 必须来自这份查询/输入链；
tags 至少含 `Name = "tfpro-c27-data-contract"` 和 `Challenge = "27"`。为资源添加
precondition，确认查询到的 Subnet 可用区等于请求值。

```powershell
terraform fmt
terraform validate
terraform plan '-out=compute.tfplan'
terraform show -no-color .\compute.tfplan
terraform apply .\compute.tfplan
Remove-Item -LiteralPath .\compute.tfplan
```

计划应只创建 1 台 EC2 instance，不应创建 VPC、Subnet 或 AMI。

## Task 5：发布单一、可审计的最终输出

删除两个临时输出，添加 `compute_contract`。它应包含 local 合同的全部选择信息，以及实际
instance ID；所有字段都必须引用 variable、data source 或 resource，不能复制运行时字符串。

```powershell
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output -json compute_contract | ConvertFrom-Json | ConvertTo-Json -Depth 5
terraform state list
terraform plan
```

state 应含三个 data source 和一个 managed instance；第二次 plan 必须为 `No changes`。

## Task 6：从 State 与 API 双向验收并清理

```powershell
$contract = terraform output -json compute_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $contract.instance_id `
  --query 'Reservations[].Instances[].{Id:InstanceId,Image:ImageId,Subnet:SubnetId,Type:InstanceType}'
terraform state show aws_instance.exercise
terraform destroy -auto-approve
terraform state list
```

API 的 Image、Subnet、Type 必须与合同一致；销毁后 state 为空。删除运行产物：

```powershell
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate, .\terraform.tfstate.backup `
  -ErrorAction SilentlyContinue
Get-ChildItem -File -Filter '*.tfplan' | Remove-Item -Force
Get-ChildItem -Force | Select-Object Name
```

最终目录只能包含 `Readme.md` 和 `challenge-27.tf`。

## LocalStack 提醒

- 内置 AMI catalog 会随 LocalStack 版本变化；依赖过滤合同，不依赖示例运行产生的 ID。
- 默认 VPC/Subnet 是模拟对象；其他练习若删除它们，应先重启或重建干净环境。
- LocalStack EC2 不运行真实 guest，本题不以 SSH、user-data 执行结果或公网连通性验收。
