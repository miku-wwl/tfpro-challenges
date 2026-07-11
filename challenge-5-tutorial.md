# Challenge 5 解题教程

## 验证说明

本教程使用 Terraform v1.14.0、AWS Provider v5.80.0、Docker 29.4.3 和 LocalStack Community v4.14.0 完整实测。实际覆盖：创建 2 个 VPC/4 个子网、data source、2 个 EC2、2 个安全组、4 条 CSV 规则、三个模块、S3 backend 迁移、remote state、14 个资源 import、两次零变更验收和分层 destroy。

LocalStack 实测 `terraform init -migrate-state -force-copy` 后，S3 中的 `vpc.tfstate` 为 10725 字节；`infra/others` 能读取其中的 `subnet_ids` 和 `vpc_id`。LocalStack 的资源 ID 与真实 AWS 不同，正式操作必须使用 state/output/CLI 查询实际 ID。

## 题目目标

先在单一 root 中创建网络、EC2 和 CSV 驱动的安全组规则，再拆成 VPC/EC2/SG 模块。VPC state 迁移到 S3，其他资源通过 remote state 获取网络输出并 import，最终按依赖顺序销毁。

## 开始前检查

```powershell
docker run -d --name challenge5-localstack -p 4567:4566 `
  -e SERVICES=ec2,s3,sts localstack/localstack:4.14.0
Invoke-RestMethod http://localhost:4567/_localstack/health
Set-Location challenge-5\base-folder
```

LocalStack 实验副本的 provider 指向 4567；正式 AWS 删除测试参数：

```hcl
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  endpoints {
    ec2 = "http://localhost:4567"
    s3  = "http://localhost:4567"
    sts = "http://localhost:4567"
  }
}
```

## Task 1：创建基础资源

```powershell
terraform init
terraform validate
terraform apply -auto-approve
terraform state list
```

预期 base 配置创建 2 个 VPC 和 4 个子网，共 6 个资源。记录所有 VPC/subnet ID，后续 import 使用。

## Task 2：查询目标 VPC 的两个子网

在 `base-folder/datasource.tf` 添加：

```hcl
data "aws_vpc" "challenge_5" {
  filter {
    name   = "tag:Name"
    values = ["challenge-5-vpc"]
  }
}

data "aws_subnet" "selected" {
  for_each = toset(["subnet-subnet1", "subnet-subnet2"])

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.challenge_5.id]
  }
  filter {
    name   = "tag:Name"
    values = [each.key]
  }
}

output "subnet_ids" {
  value = { for name, subnet in data.aws_subnet.selected : name => subnet.id }
}
```

必须同时按 VPC ID 和 Name 过滤，因为 random VPC 中存在同名子网。运行 `terraform apply -auto-approve` 和 `terraform output subnet_ids`，预期返回两个不同 ID。

## Task 3：在查询出的子网创建 EC2

在 `base-folder/ec2.tf` 添加唯一的实例 block：

```hcl
resource "aws_instance" "app" {
  for_each = data.aws_subnet.selected

  ami           = "<US_EAST_1_AMI_ID>"
  instance_type = "t2.micro"
  subnet_id     = each.value.id

  tags = { Name = "ec2-${each.key}" }
}
```

AMI 必须在真实 AWS 的 `us-east-1` 可用。实例地址为：

```text
aws_instance.app["subnet-subnet1"]
aws_instance.app["subnet-subnet2"]
```

## Task 4：创建两个安全组

在 `base-folder/sg.tf` 添加：

```hcl
resource "aws_security_group" "app" {
  for_each = toset(["app-1-sg", "app-2-sg"])
  name     = each.key
  vpc_id   = data.aws_vpc.challenge_5.id
}
```

## Task 5：根据 CSV 创建规则

同一文件先解析并过滤 CSV：

```hcl
locals {
  sg_rules = csvdecode(file("${path.module}/sg.csv"))

  ingress_rules = {
    for rule in local.sg_rules : "${rule.name}-${rule.port}" => rule
    if rule.description == "app-1" && rule.direction == "in"
  }
  egress_rules = {
    for rule in local.sg_rules : "${rule.name}-${rule.port}" => rule
    if rule.description == "app-2" && rule.direction == "out"
  }
}
```

再添加各一个 ingress/egress block：

```hcl
resource "aws_vpc_security_group_ingress_rule" "app_1" {
  for_each          = local.ingress_rules
  security_group_id = aws_security_group.app["app-1-sg"].id
  cidr_ipv4         = each.value.cidr_block
  from_port         = tonumber(each.value.port)
  to_port           = tonumber(each.value.port)
  ip_protocol       = each.value.protocol
  description       = each.value.description
}

resource "aws_vpc_security_group_egress_rule" "app_2" {
  for_each          = local.egress_rules
  security_group_id = aws_security_group.app["app-2-sg"].id
  cidr_ipv4         = each.value.cidr_block
  from_port         = tonumber(each.value.port)
  to_port           = tonumber(each.value.port)
  ip_protocol       = each.value.protocol
  description       = each.value.description
}
```

预期只保留 app-1 入站 80/443 和 app-2 出站 8443/9000。数据链为 `file → csvdecode → for 过滤 → map → for_each`。

## Task 6：创建 Task 2～5 资源

```powershell
terraform fmt -recursive
terraform validate
terraform plan
terraform apply -auto-approve
terraform state list
```

预期新增 8 个资源：2 EC2、2 SG、4 rules。完整配置共 14 个资源，随后 `terraform plan` 应为 `No changes`。

## Task 7：创建目录

```text
challenge-5/
├── base-folder/
├── infra/
│   ├── vpc-infra/
│   └── others/
└── modules/
    ├── vpc/
    ├── ec2/
    └── sg/
```

## Task 8：拆分模块

- `modules/vpc`：两个 `aws_vpc`、两组 `aws_subnet`，输出目标 `subnet_ids` 和 `vpc_id`。
- `modules/ec2`：接收 `map(string)` 类型的 `subnet_ids`，保留唯一 EC2 block。
- `modules/sg`：接收 `vpc_id`，包含两个 SG 和两类 rule；把 `sg.csv` 一并放入模块，并用 `${path.module}/sg.csv` 读取。

VPC 模块输出：

```hcl
output "subnet_ids" {
  value = { for key, subnet in aws_subnet.challenge_5 : "subnet-${key}" => subnet.id }
}
output "vpc_id" { value = aws_vpc.main.id }
```

EC2/SG 输入：

```hcl
variable "subnet_ids" { type = map(string) }
variable "vpc_id" { type = string }
```

重构后暂时不要在 base-folder apply，否则旧配置与新 roots 会同时管理资源。

## Task 9：VPC state 迁移到 S3

先手工创建全局唯一 bucket：

```powershell
aws s3api create-bucket --bucket '<STATE_BUCKET>' --region us-east-1
```

`infra/vpc-infra/main.tf` 先只调用模块并输出：

```hcl
module "vpc" { source = "../../modules/vpc" }
output "subnet_ids" { value = module.vpc.subnet_ids }
output "vpc_id" { value = module.vpc.vpc_id }
```

在没有 backend block 时 `terraform init`，用实际 ID import 6 个资源：

```powershell
terraform import module.vpc.aws_vpc.main '<CHALLENGE_VPC_ID>'
terraform import 'module.vpc.aws_subnet.challenge_5[\"subnet1\"]' '<SUBNET1_ID>'
terraform import 'module.vpc.aws_subnet.challenge_5[\"subnet2\"]' '<SUBNET2_ID>'
terraform import module.vpc.aws_vpc.random '<RANDOM_VPC_ID>'
terraform import 'module.vpc.aws_subnet.random[\"subnet1\"]' '<RANDOM_SUBNET1_ID>'
terraform import 'module.vpc.aws_subnet.random[\"subnet2\"]' '<RANDOM_SUBNET2_ID>'
terraform plan
```

目标是本地 state 有 6 个地址且 `No changes`。先备份：

```powershell
terraform state pull | Set-Content -Encoding utf8 state-before-s3-migration.json
```

再加入正式 S3 backend：

```hcl
terraform {
  backend "s3" {
    bucket = "<STATE_BUCKET>"
    key    = "vpc.tfstate"
    region = "us-east-1"
  }
}
```

迁移并验证：

```powershell
terraform init -migrate-state
terraform state list
terraform output
aws s3api head-object --bucket '<STATE_BUCKET>' --key vpc.tfstate
terraform plan
```

LocalStack backend 需额外设置 `use_path_style`、`skip_*`、测试凭证、`skip_s3_checksum` 和 `endpoints = { s3 = "http://localhost:4567" }`。实测迁移后远端对象存在且 plan 为零变更。

难点入口：搜索 `Terraform S3 backend migrate state`；官网：[S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)。

## Task 10：导入 EC2 与 SG

`infra/others/main.tf` 的 remote state 只能定义在 root：

```hcl
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "<STATE_BUCKET>"
    key    = "vpc.tfstate"
    region = "us-east-1"
  }
}

module "ec2" {
  source     = "../../modules/ec2"
  subnet_ids = data.terraform_remote_state.vpc.outputs.subnet_ids
}
module "sg" {
  source = "../../modules/sg"
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id
}
```

先从旧 state/CLI取得实例、SG 和 rule ID，备份旧 state，再 import：

```powershell
terraform init
terraform import 'module.ec2.aws_instance.app[\"subnet-subnet1\"]' '<INSTANCE1_ID>'
terraform import 'module.ec2.aws_instance.app[\"subnet-subnet2\"]' '<INSTANCE2_ID>'
terraform import 'module.sg.aws_security_group.app[\"app-1-sg\"]' '<APP1_SG_ID>'
terraform import 'module.sg.aws_security_group.app[\"app-2-sg\"]' '<APP2_SG_ID>'
terraform import 'module.sg.aws_vpc_security_group_ingress_rule.app_1[\"sg01-443\"]' '<RULE_443_ID>'
terraform import 'module.sg.aws_vpc_security_group_ingress_rule.app_1[\"sg01-80\"]' '<RULE_80_ID>'
terraform import 'module.sg.aws_vpc_security_group_egress_rule.app_2[\"sg02-8443\"]' '<RULE_8443_ID>'
terraform import 'module.sg.aws_vpc_security_group_egress_rule.app_2[\"sg02-9000\"]' '<RULE_9000_ID>'
terraform state list
terraform plan
```

预期 remote state 可读、8 个资源地址存在且 `No changes`。确认新 states 完整后，归档 base-folder 旧 state，禁止再用旧 state apply/destroy，避免双重管理。

难点入口：搜索 `Terraform remote state S3 module import for_each`；官网：[terraform_remote_state](https://developer.hashicorp.com/terraform/language/state/remote-state-data)、[Import](https://developer.hashicorp.com/terraform/cli/import)。

## Task 11：销毁

必须先销毁依赖网络的 others，再销毁 VPC，最后删 backend bucket：

```powershell
terraform -chdir=infra/others plan -destroy
terraform -chdir=infra/others destroy -auto-approve
terraform -chdir=infra/others state list

terraform -chdir=infra/vpc-infra plan -destroy
terraform -chdir=infra/vpc-infra destroy -auto-approve
terraform -chdir=infra/vpc-infra state list

aws s3 rm 's3://<STATE_BUCKET>' --recursive
aws s3api delete-bucket --bucket '<STATE_BUCKET>'
```

不要运行 base-folder 的旧 state destroy。最终确认实例、SG、两个 VPC、四个子网和 state bucket 均不存在。

## 最终检查

- data subnet 同时按 VPC ID和 Name 过滤，输出恰好两个 ID。
- 只有一个 EC2、一个 SG、一个 ingress、一个 egress resource block。
- CSV 最终生成 2 入站 + 2 出站规则。
- VPC local state 已实际迁移到 S3 的 `vpc.tfstate`。
- VPC root 输出 `subnet_ids`、`vpc_id`，others root 成功读取。
- VPC 6 个、others 8 个资源 import 后均为零变更。
- 销毁顺序为 others → vpc-infra → backend bucket，最终无遗留。
