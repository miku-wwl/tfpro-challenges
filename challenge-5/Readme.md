## Challenge 5

本挑战用于练习 data source、模块化、远程 backend 和资源 import 等 Terraform 概念。请按顺序完成任务。

### 任务 1：创建基础资源

1. 进入 `base-folder`。
2. 运行以下命令创建初始资源：

`terraform apply -auto-approve`

### 任务 2：定义 Data Source

* 在 `base-folder` 中创建 `datasource.tf`。
* 定义 data source，从自定义 VPC `challenge-5-vpc` 中获取名为 `subnet-subnet1` 和 `subnet-subnet2` 的两个子网 ID。
* 使用名为 `subnet_ids` 的 output 显示获取到的子网 ID。

### 任务 3：在自定义子网中创建 EC2 实例

* 在 base-folder 中创建 `ec2.tf`。
* 只定义一个 `aws_instance` resource block，并根据需要使用 `for_each` 遍历数据以创建两个 EC2 实例：
  * 一个 EC2 位于 `subnet-subnet1`（子网 ID 来自任务 2）。
  * 另一个 EC2 位于 `subnet-subnet2`（子网 ID 来自任务 2）。

* 两个 EC2 实例使用相同的 AMI 和实例类型：
  * `ami` 使用 LocalStack 中可用的 AMI ID，例如 `ami-00000000000000000`。
  * `instance_type` 使用 `t2.micro`。
* `subnet_id` 必须引用任务 2 的 Data Source 输出，不得硬编码子网 ID。

> [!NOTE]
> 必须通过查询 data source 引用 `subnet_id`，不得硬编码。

### 任务 4：创建 Security Group

* 在 base-folder 中创建 `sg.tf`。
* 定义一个 `aws_security_group` resource block，并使用 `for_each` 创建两个 Security Group：
  * `app-1-sg`
  * `app-2-sg`
* 确保 Security Group 创建在 `challenge-5-vpc` 中。

### 任务 5：创建 Security Group Rule

参考 `sg.csv` 的内容，并按照以下条件创建 Security Group Rule：

1. 使用一个 `aws_vpc_security_group_ingress_rule` resource block，为 `app-1-sg` 创建入站规则。
   * 如果 CSV 中的 `description` 为 `app-1`，则该规则必须关联到 `app-1-sg`。只处理入站规则，忽略出站规则。

2. 使用一个 `aws_vpc_security_group_egress_rule` resource block，为 `app-2-sg` 创建出站规则。
   * 如果 CSV 中的 `description` 为 `app-2`，则该规则必须关联到 `app-2-sg`。只处理出站规则，忽略入站规则。

> [!IMPORTANT]
> 使用 `for_each` 和 `for` 表达式遍历 CSV 文件内容并获取所需数据。

### 任务 6：创建所需资源

运行以下命令创建前面任务中定义的资源：

`terraform apply -auto-approve`

### 任务 7：创建目录结构

在 challenge-5 目录中创建以下结构：

```sh
challenge-5
├── base-folder
├── infra
│   ├── vpc-infra
│   └── others
└── modules
    ├── vpc
    ├── ec2
    └── sg
```

### 任务 8：重构代码

将以下资源类型从 `base-folder` 移动到 `vpc` 子模块：

| 资源类型 | 子模块目录 |
| :--- | :---: |
| `aws_vpc` | vpc |
| `aws_subnet` | vpc |

将以下资源类型从 `base-folder` 移动到 `ec2` 子模块：

| 资源类型 | 子模块目录 |
| :--- | :---: |
| `aws_instance` | `ec2` |

将以下资源类型从 `base-folder` 移动到 `sg` 子模块：

| 资源类型 | 子模块目录 |
| :--- | :---: |
| `aws_security_group` | sg |
| `aws_vpc_security_group*` | sg |

### 任务 9：为 VPC-Infra 使用 S3 Backend

从本任务开始，`infra/vpc-infra` 和 `infra/others` 分别作为两个独立的
Terraform Root Module 使用。它们各自拥有独立的配置和 State，不要在
`challenge-5` 顶层创建统一的 Root Module 来调用这两个目录。

在 AWS 账户中手动创建 S3 Bucket。

在 `infra/vpc-infra` 目录中：

* 使用 module source 调用 `vpc` 子模块。
* 导入现有 VPC 和子网资源。
* 配置 S3 backend，将 state 文件存储为 `vpc.tfstate`。
* 将本地 state 迁移到 S3 backend。

### 任务 10：导入 EC2 和 SG 基础设施

在 `infra/others` 目录中：

* 使用 module source 引用 `ec2` 和 `sg` 子模块。
* 使用 `terraform_remote_state` 从 `vpc.tfstate` 获取子网 ID。
* 只在根模块中定义 `terraform_remote_state`，不要在子模块中定义。
* 导入现有 EC2 和 Security Group 资源。

> [!TIP]
> 确保 `vpc.tfstate` 的 output 包含两个子网的 `subnet_ids`。

### 任务 11：销毁基础设施

销毁本挑战中创建的所有基础设施。
