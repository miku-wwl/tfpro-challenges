# Challenge 4 解题教程

## 验证说明

本教程已使用 Terraform v1.14.0、AWS Provider v5.80.0、Docker 29.4.3 和 LocalStack Community v4.14.0 完整实测。实际执行了 `init`、`validate`、`plan`、创建两个 EC2 实例、检查 state/output、零变更 plan 和 destroy。

实测只创建 `aws_instance.this[0]` 与 `[1]`：类型分别为 `t2.micro`、`t3.nano`，Name 标签分别为 `Security`、`DevOps`；另外两个非 `us-east-1` CSV 行未创建。LocalStack 返回了 subnet ID，但没有在 `vpc_security_group_ids` 中返回默认安全组，因此实验 output 的 `firewall_id` 是空集合；真实 AWS 通常会返回默认或显式关联的安全组 ID。

## 题目目标

读取并解析 `ec2.csv`，只保留 `us-east-1` 数据；在唯一的 `aws_instance` block 内使用 `count` 和 `count.index` 创建实例，同时转换实例类型并设置 Team Name 标签。最后输出每个实例的 ID、区域、团队、CSV 类型、子网和安全组 ID。

## 开始前检查

进入题目目录并确认 CSV 表头未改变：

```powershell
Set-Location challenge-4
Get-Content ec2.csv
aws sts get-caller-identity
```

正式 AWS 中确认题目 AMI 在 `us-east-1` 可用。LocalStack 实验可启动独立容器；如果 4566 已占用，可改绑 4567：

```powershell
docker run -d --name challenge4-localstack -p 4567:4566 `
  -e SERVICES=ec2,sts localstack/localstack:4.14.0
docker ps --filter 'name=challenge4-localstack'
Invoke-RestMethod http://localhost:4567/_localstack/health
```

LocalStack 实验副本使用以下 provider；正式考试配置必须删除 endpoint、测试凭证和 `skip_*` 参数：

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
    sts = "http://localhost:4567"
  }
}
```

## Task 1：根据 CSV 创建 EC2

### 解题思路

- `file` 读取字符串，`csvdecode` 将每行转换为对象。
- 在 `locals` 中用 for expression 过滤区域；题目只禁止在 `aws_instance` block 内使用 for/for_each。
- `count` 等于过滤后列表长度，`count.index` 取得当前行。
- 用 `lookup` 将 `micro`/`nano` 映射为实际 AWS 实例类型。

新建 `main.tf`。正式 AWS provider 使用标准配置：

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  ec2_data = [
    for row in csvdecode(file("${path.module}/ec2.csv")) : row
    if row.Region == "us-east-1"
  ]
}

resource "aws_instance" "this" {
  count = length(local.ec2_data)

  ami = local.ec2_data[count.index].AMI_ID
  instance_type = lookup(
    {
      micro = "t2.micro"
      nano  = "t3.nano"
    },
    local.ec2_data[count.index].instance_type
  )

  tags = {
    Name = local.ec2_data[count.index].Team_Name
  }
}
```

数据转换链如下：

```text
file(ec2.csv)
  → csvdecode：tuple(object)
  → 过滤 Region == us-east-1
  → 2 个对象组成的 tuple
  → count = 2
  → aws_instance.this[0] / [1]
```

可以先用 console 检查过滤结果：

```powershell
terraform init
terraform console
```

输入 `local.ec2_data`，预期只显示 Security/micro 与 DevOps/nano 两行。退出后执行：

```powershell
terraform fmt
terraform validate
terraform plan '-out=challenge4.tfplan'
terraform show challenge4.tfplan
```

计划必须是 `2 to add, 0 to change, 0 to destroy`，并同时满足：

- `[0]`：AMI `ami-01816d07b1128cd2d`、`t2.micro`、Name `Security`；
- `[1]`：同一 AMI、`t3.nano`、Name `DevOps`；
- 不包含 `ap-south-1` 或 `ap-southeast-1` 的行。

确认后应用并检查：

```powershell
terraform apply challenge4.tfplan
terraform state list
terraform state show 'aws_instance.this[0]'
terraform state show 'aws_instance.this[1]'
```

PowerShell 中含 `[]` 的资源地址应整体放在单引号中。预期 state 只有两个地址，类型和 Name 标签与上述计划一致。

### 难点与官网入口

- 搜索关键词：`Terraform csvdecode file filter for expression count index`
- 官网：[csvdecode](https://developer.hashicorp.com/terraform/language/functions/csvdecode)、[For expressions](https://developer.hashicorp.com/terraform/language/expressions/for)、[count](https://developer.hashicorp.com/terraform/language/meta-arguments/count)

## Task 2：输出实例信息

在 `main.tf` 添加：

```hcl
output "running_ec2" {
  value = [
    for index, instance in aws_instance.this : {
      id          = instance.id
      region      = local.ec2_data[index].Region
      team        = local.ec2_data[index].Team_Name
      type        = local.ec2_data[index].instance_type
      subnet      = instance.subnet_id
      firewall_id = instance.vpc_security_group_ids
    }
  ]
}
```

这里的 `type` 保留 CSV 中的 `micro`/`nano`，与题目示例一致；实际创建类型可在 `terraform state show` 的 `instance_type` 中看到 `t2.micro`/`t3.nano`。`firewall_id` 使用 set 类型的 `vpc_security_group_ids`，因此 CLI 显示为 `toset([...])`。

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve
terraform output running_ec2
terraform output -json running_ec2
```

预期 plan 为 `No changes`，output 有两个对象。每个对象都包含：

- 非空的 `id` 和 `subnet`；
- `region = "us-east-1"`；
- `team` 分别为 `Security`、`DevOps`；
- `type` 分别为 `micro`、`nano`；
- `firewall_id` 为安全组 ID集合。

LocalStack Community v4.14.0 实测 `vpc_security_group_ids = []`，所以本地 `firewall_id = toset([])`；这是模拟差异。真实 AWS 若同样为空，应检查实例网络接口和安全组关联，不要为了凑输出而硬编码 `sg-...`。

难点入口：搜索 `Terraform output for expression resource count instances`；官网：[Output values](https://developer.hashicorp.com/terraform/language/values/outputs)。

## 销毁验证资源

教程验证完成后先检查范围，再销毁：

```powershell
terraform plan -destroy
terraform destroy -auto-approve
terraform state list
```

预期只销毁 `aws_instance.this[0]`、`[1]`，最终 state 为空。真实 AWS 可再确认没有运行实例：

```powershell
aws ec2 describe-instances `
  --filters Name=instance-state-name,Values=pending,running,stopping,stopped `
  --query 'Reservations[].Instances[?Tags[?Key==`Name` && (Value==`Security` || Value==`DevOps`)]].InstanceId'
```

## 最终检查

- 只有一个 `aws_instance` resource block。
- resource 内使用 `count` 和 `count.index`，没有 `for_each` 或 for expression。
- CSV 过滤后只创建两个 `us-east-1` 实例。
- `micro → t2.micro`、`nano → t3.nano` 转换正确。
- Name 标签来自 `Team_Name`。
- `running_ec2` 含 2 个对象和题目要求的 6 个字段。
- apply 后 plan 为零变更；destroy 后 state 为空。
