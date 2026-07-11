# Challenge 8 解题教程

## 验证说明

本教程已使用 Terraform v1.14.0、AWS Provider v5.82.2、Docker 29.4.3 和 LocalStack Community v4.14.0 实际验证。为避免影响本机已有的 `localhost:4566`，本次使用独立容器并将 LocalStack 映射到 `localhost:4567`。

验证覆盖了 base-folder 创建 VPC/子网、根目录数据源查询、CSV 转换、创建安全组和 6 条入站规则、output、零变更 plan，以及按正确顺序完整 destroy。LocalStack 的 EC2 模拟足以覆盖本题所用功能，未发现影响答案的真实 AWS 差异；正式考试代码仍使用题目给出的标准 AWS Provider，不应加入 LocalStack endpoint、测试凭证或跳过校验参数。

## 题目目标

先创建 `central-vpc` 和 3 个子网，再通过 data source 查询其 ID 与 CIDR。读取 `sg.csv`，只把入站记录转换成 `aws_vpc_security_group_ingress_rule`，并输出转换后的数据。

## 开始前检查

仓库中有两个独立 Terraform 工作目录：

```text
challenge-8/base-folder/   # VPC 和子网，一个 state
challenge-8/               # 数据源、安全组和规则，另一个 state
```

真实 AWS 考试环境先确认当前身份和区域：

```bash
aws sts get-caller-identity
terraform version
```

还要确认目标账户中没有另一个同名 `central-vpc`。本题用名称查询单个 VPC；存在重名资源时，`aws_vpc` data source 会因结果不唯一而失败。

LocalStack 验证可使用独立容器：

```bash
docker run -d --name codex-challenge8-localstack \
  -p 4567:4566 \
  -e SERVICES=ec2,sts \
  localstack/localstack:4.14.0

curl http://localhost:4567/_localstack/health
```

LocalStack 的 provider override 只能放在实验副本中，不能写入最终考试答案。

## Task 1：创建基础资源

进入 base-folder 初始化并创建题目提供的资源：

```bash
cd challenge-8/base-folder
terraform init
terraform validate
terraform plan
terraform apply -auto-approve
terraform state list
```

预期 state 中有 4 个资源：

```text
aws_vpc.central_vpc
aws_subnet.subnets["app"]
aws_subnet.subnets["central"]
aws_subnet.subnets["database"]
```

实际验证结果为 `Resources: 4 added, 0 changed, 0 destroyed`。不要在此时销毁，因为根目录的数据源和安全组需要这些资源。

## Task 2：通过 data source 查询子网

回到 `challenge-8` 根目录，新建 `datasource.tf`。先按 Name 查询 VPC，再把 VPC ID 与 3 个子网名称一起作为筛选条件：

```hcl
data "aws_vpc" "central" {
  filter {
    name   = "tag:Name"
    values = ["central-vpc"]
  }
}

data "aws_subnets" "central" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.central.id]
  }

  filter {
    name   = "tag:Name"
    values = ["app-subnet", "database-subnet", "central-subnet"]
  }
}

data "aws_subnet" "selected" {
  for_each = toset(data.aws_subnets.central.ids)
  id       = each.value
}
```

`aws_subnets` 返回 ID 集合，但后续还需要每个子网的 Name tag 和 CIDR，所以再以 ID 为 key 查询 `aws_subnet`。在同一文件继续建立便于查找的 map，并按题目要求输出名称与 ID：

```hcl
locals {
  subnet_by_name = {
    for subnet in data.aws_subnet.selected : subnet.tags.Name => {
      id         = subnet.id
      cidr_block = subnet.cidr_block
    }
  }
}

output "subnet_ids" {
  value = {
    for name, subnet in local.subnet_by_name : name => subnet.id
  }
}
```

预期 `subnet_ids` 有 `app-subnet`、`database-subnet` 和 `central-subnet` 三个 key；具体 `subnet-...` ID 必须以实际 output 为准。

难点入口：搜索 `Terraform AWS data aws_subnets filter tags`；参见 [`aws_subnets` data source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) 和 [For expressions](https://developer.hashicorp.com/terraform/language/expressions/for)。

## Task 3：创建安全组

在根目录新建 `main.tf`，加入：

```hcl
resource "aws_security_group" "kplabs" {
  name   = "kplabs-sg"
  vpc_id = data.aws_vpc.central.id
}
```

VPC ID 来自 Task 2 的 data source，不要从 base-folder 的 state 文件中复制或写死。

## Task 4：从 CSV 创建入站规则

先在 `main.tf` 中读取 CSV、定义题目给出的名称映射并转换端口：

```hcl
locals {
  sg_data = csvdecode(file("${path.module}/sg.csv"))

  source_subnet = {
    app          = "app-subnet"
    database     = "database-subnet"
    monitoring   = "central-subnet"
    "anti-virus" = "central-subnet"
  }

  filtered_data = {
    for index, rule in local.sg_data : tostring(index) => {
      cidr_block = local.subnet_by_name[local.source_subnet[rule.cidr_block]].cidr_block
      from_port  = tonumber(split("-", rule.port)[0])
      to_port    = tonumber(split("-", rule.port)[length(split("-", rule.port)) - 1])
      protocol   = rule.protocol
      name       = rule.name
    } if rule.direction == "in"
  }
}
```

这里有三个关键点：

- `if rule.direction == "in"` 排除 CSV 最后两条 `out` 记录。
- 单端口 `80` 经 `split` 后首尾都是 80；范围 `8081-8085` 的首尾分别成为 `from_port` 和 `to_port`。
- `tonumber` 把 `csvdecode` 得到的字符串转换为资源参数需要的数字。

然后用转换后的 map 创建规则：

```hcl
resource "aws_vpc_security_group_ingress_rule" "rules" {
  for_each = local.filtered_data

  security_group_id = aws_security_group.kplabs.id
  cidr_ipv4         = each.value.cidr_block
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  ip_protocol       = each.value.protocol
  description       = each.value.name
}
```

预期产生 6 个实例，地址为 `aws_vpc_security_group_ingress_rule.rules["0"]` 至 `...["5"]`。在 PowerShell 或 Bash 中查询带索引的地址时要用单引号包住完整地址：

```bash
terraform state show 'aws_vpc_security_group_ingress_rule.rules["4"]'
```

难点入口：搜索 `Terraform csvdecode for expression filter split string`；参见 [`csvdecode`](https://developer.hashicorp.com/terraform/language/functions/csvdecode)、[`split`](https://developer.hashicorp.com/terraform/language/functions/split) 和 [`aws_vpc_security_group_ingress_rule`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule)。

## Task 5：输出转换结果

在 `main.tf` 末尾加入 output，只展示题目要求的 3 个字段：

```hcl
output "filtered_data" {
  value = {
    for key, rule in local.filtered_data : key => {
      cidr_block = rule.cidr_block
      from_port  = rule.from_port
      to_port    = rule.to_port
    }
  }
}
```

在 `challenge-8` 根目录执行：

```bash
terraform fmt
terraform init
terraform validate
terraform plan
terraform apply -auto-approve
terraform output
terraform state list
terraform plan
```

实际验证结果：

- apply 创建 1 个 `kplabs-sg` 和 6 条入站规则，共 7 个资源。
- `filtered_data["0"]` 是 `10.0.1.0/24:80-80`。
- `filtered_data["1"]`、`["2"]` 分别是 `10.0.2.0/24:3306-3306` 和 `:5432-5432`。
- `filtered_data["3"]` 至 `["5"]` 使用 `10.0.3.0/24`，端口分别为 `8080-8080`、`8081-8085`、`443-443`。
- state 中没有出站规则实例，最终 plan 显示 `No changes`。

## Task 6：按依赖顺序销毁

根目录和 base-folder 使用两个独立 state，Terraform 无法跨 state 自动计算销毁顺序。必须先销毁引用 VPC 的规则和安全组，再销毁子网和 VPC。

先在 `challenge-8` 根目录执行并确认计划只销毁 7 个根目录资源：

```bash
terraform plan -destroy
terraform destroy -auto-approve
terraform state list
```

实际验证为 `Resources: 7 destroyed`，随后根目录 `state list` 不再列出托管资源。再进入 base-folder：

```bash
cd base-folder
terraform plan -destroy
terraform destroy -auto-approve
terraform state list
```

实际验证为 `Resources: 4 destroyed`，最后 state 为空。如果反过来先删除 VPC，AWS 会因为仍有关联的安全组而拒绝操作。

## 最终检查

- base-folder 的 1 个 VPC 和 3 个子网已先创建成功。
- `subnet_ids` 按子网名称输出 3 个动态 ID，没有写死资源 ID。
- `kplabs-sg` 位于 data source 查到的 `central-vpc`。
- CSV 的 6 条入站记录全部创建，2 条出站记录全部排除。
- `app`、`database`、`monitoring`、`anti-virus` 均映射到题目指定的子网 CIDR。
- 单端口和端口范围都得到正确的 `from_port`、`to_port`。
- apply 后最终 plan 为零变更。
- destroy 先根目录、后 base-folder，两个 state 最终均无资源。
- 实验结束后只删除自己启动的容器：

  ```bash
  docker rm -f codex-challenge8-localstack
  ```
