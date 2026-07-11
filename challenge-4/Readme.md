## Challenge 4

本挑战考查使用外部数据文件、遍历数据以及通过 Terraform 动态创建 AWS 资源的能力。

### 任务 1：创建 EC2 实例

根据 `ec2.csv` 的内容和以下条件创建 EC2 实例：

1. 仅当 Region 为 `us-east-1` 时创建 EC2 实例。

2. 在 `aws_instance` 资源类型中，必须使用 `count` 和 `count.index` 遍历数据。不得在 `aws_instance` 资源类型中使用 `for_each` 或 `for` 表达式，但可以在其他位置使用。解决方案中只能有一个 `aws_instance` resource block。

3. 确保根据 CSV 文件内容动态设置 `instance_type` 和 `ami_id`。

4. 按照下表在 `aws_instance` 资源中替换 CSV 的 `instance_type` 值：

| CSV 中的值 | 实际使用的值 |
| :--- | :---: |
| `micro` | t2.micro |
| `nano` | t3.nano |

5. 将 CSV 中的 `Team_Name` 映射到 EC2 实例的 `Name` tag。

### 任务 2：输出值

创建 output，为每个已创建的 EC2 实例显示以下信息：

```sh
Instance ID
Region
Team name
Instance type
Subnet ID
Security Group ID (firewall_id)
```

下面提供了参考输出。输出格式应与其类似，实际值可以不同。

```sh
running_ec2 = [
  {
    "firewall_id" = toset([
      "sg-06dc77ed59c310f03",
    ])
    "id" = "i-0167b045e08b6ffee"
    "region" = "us-east-1"
    "subnet" = "subnet-0ad852475eaf6952c"
    "team" = "Security"
    "type" = "micro"
  },
  # 其他实例数据……
]
```
