## Challenge 8

本挑战用于练习 data source、`for` 表达式、output value 和 local value 等 Terraform 概念。

### 任务 1：创建基础资源

1. 进入 `base-folder`。
2. 运行以下命令创建初始资源：

`terraform apply -auto-approve`

此基础任务会在 `central-vpc` 中创建以下 3 个子网：

| 子网 | VPC |
| :--- | :---: |
| `app-subnet` | central-vpc |
| `database-subnet` | central-vpc |
| `central-subnet` | central-vpc |

### 任务 2：定义 Data Source

* 在根目录创建 `datasource.tf`。
* 定义 data source，获取基础任务中创建的 3 个子网所关联的 CIDR block。
* 使用名为 `subnet_ids` 的 output，将获取到的子网 ID 与子网名称一起显示。

### 任务 3：创建 Security Group

> [!NOTE]
> 从本任务开始，Task 3、Task 4 和 Task 5 均在最外层 `challenge-8` 根目录完成，不在 `base-folder` 中修改。`base-folder` 仅用于 Task 1 创建基础资源。

在 `central-vpc` 中创建名为 `kplabs-sg` 的 Security Group。

### 任务 4：创建 VPC Security Group Ingress Rule

根据 `sg.csv` 的内容和以下条件，使用 `aws_vpc_security_group_ingress_rule` 资源类型创建 Security Group Rule。

* 只能创建入站规则。
* 根据 CSV 文件中 `cidr_block` 的值，计算下表所示的结果：

| cidr_block 的值 | 计算结果 |
| :--- | :---: |
| `app` | `app-subnet` 的 CIDR block |
| `database` | `database-subnet` 的 CIDR block |
| `monitoring` | `central-subnet` 的 CIDR block |
| `anti-virus` | `central-subnet` 的 CIDR block |

> [!NOTE]
> `split("-", rule.port)` 用于拆分 CSV 中的端口值。单端口如 `80` 会得到 `[`80`]`，端口范围如 `8081-8085` 会得到 `[`8081`, `8085`]`。因此可以取第一个元素作为 `from_port`，最后一个元素作为 `to_port`，并使用 `tonumber()` 转换为数字。

### 任务 5：输出值



使用 output 按照以下格式输出数据：

```sh
filtered_data = {
  "0" = {
    "cidr_block" = "10.0.1.0/24"
    "from_port" = 80
    "to_port" = 80
  }
  "1" = {
    "cidr_block" = "10.0.2.0/24"
    "from_port" = 3306
    "to_port" = 3306
  }
  "2" = {
    "cidr_block" = "10.0.2.0/24"
    "from_port" = 5432
    "to_port" = 5432
  }
  # 后续 output 中还应包含更多规则……
```

### 任务 6：销毁基础设施

销毁本挑战中创建的所有基础设施。
