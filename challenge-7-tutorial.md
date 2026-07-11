# Challenge 7 解题教程

## 验证说明

本教程已使用 Terraform v1.14.0、Docker 29.4.3 和 LocalStack Community v4.14.0 实际验证。为避免影响本机已有的 `localhost:4566` 环境，本次单独启动 LocalStack 容器并映射到 `localhost:4567`，健康检查正常。

Challenge 7 只考查本地 CSV 和 Terraform 表达式，没有 AWS Provider 或云资源，所以 Terraform 不会向 LocalStack 创建资源。以下答案仍已实际执行 `terraform init`、`validate`、`apply`、`output` 和最终 `plan`；`apply` 创建 0 个资源，所有 output 均得到题目要求的实值，最终 plan 显示 `No changes`。本题不存在未覆盖的真实 AWS 差异。

## 题目目标

读取 `ec2.csv`，使用 Terraform 表达式动态生成列表、集合、对象以及 map of maps。所有业务值必须来自 CSV，不能把 AMI、Region、Team 或实例类型硬编码进 output。

## 开始前检查

在仓库根目录确认题目文件：

```bash
cd challenge-7
ls
```

目录中应有 `ec2.csv`。先查看 CSV 表头，后续属性名必须与其大小写完全一致：

```bash
cat ec2.csv
```

本次验证使用以下命令启动独立 LocalStack；若端口 `4566` 空闲，也可以改用 `4566:4566`：

```bash
docker run -d --name codex-challenge7-localstack \
  -p 4567:4566 \
  -e SERVICES=sts \
  localstack/localstack:4.14.0

curl http://localhost:4567/_localstack/health
```

健康检查中应看到 LocalStack 版本和服务状态。由于本题没有 AWS Provider，LocalStack 只用于满足实验环境检查，不参与表达式求值。

## Task 1：读取 CSV

在 `challenge-7` 目录新建 `main.tf`，先加入：

```hcl
locals {
  ec2_data = csvdecode(file("${path.module}/ec2.csv"))
}
```

数据流是 `file` 读取字符串，`csvdecode` 再把它转换为对象组成的序列；每个对象的属性名来自 CSV 第一行。`${path.module}` 可保证从其他目录调用 Terraform 时仍能找到文件。

难点入口：搜索 `Terraform csvdecode file`；参见 [`file`](https://developer.hashicorp.com/terraform/language/functions/file) 和 [`csvdecode`](https://developer.hashicorp.com/terraform/language/functions/csvdecode)。

## Task 2：AMI ID 列表

在 `main.tf` 中加入：

```hcl
output "list_amis" {
  value = [for row in local.ec2_data : row.AMI_ID]
}
```

`for` 按 CSV 行顺序取出 `AMI_ID`，结果是字符串序列。没有在 output 中写死任何 AMI。

## Task 3：唯一 Team 列表

继续加入：

```hcl
output "unique_team_names" {
  value = sort(tolist(toset([for row in local.ec2_data : row.Team_Name])))
}
```

先用 `for` 取值，`toset` 去重，`tolist` 转回题目要求的列表，最后 `sort` 固定显示顺序。验证结果应是 `DevOps`、`SRE`、`Security`。

难点入口：搜索 `Terraform convert set to sorted list`；参见 [`toset`](https://developer.hashicorp.com/terraform/language/functions/toset)、[`tolist`](https://developer.hashicorp.com/terraform/language/functions/tolist) 和 [`sort`](https://developer.hashicorp.com/terraform/language/functions/sort)。

## Task 4：Region 的 list of lists

继续加入：

```hcl
output "regions_list_of_lists" {
  value = [for row in local.ec2_data : [row.Region]]
}
```

外层 `for` 生成一个列表；表达式中的 `[row.Region]` 又为每一行生成只含一个 Region 的内层列表。

## Task 5：只保留 nano 的 list of lists

继续加入：

```hcl
output "list_list_condition" {
  value = [for row in local.ec2_data : [row.Region] if row.instance_type == "nano"]
}
```

`if` 放在结果表达式之后，用来过滤 CSV 行。预期只输出 `ap-south-1` 和 `us-east-1` 两个内层列表。

难点入口：搜索 `Terraform for expression filtering`；参见 [For expressions](https://developer.hashicorp.com/terraform/language/expressions/for)。

## Task 6：按实例类型计数

继续加入：

```hcl
output "instance_count_by_type" {
  value = {
    for instance_type in toset([for row in local.ec2_data : row.instance_type]) :
    instance_type => length([
      for row in local.ec2_data : row
      if row.instance_type == instance_type
    ])
  }
}
```

外层表达式先从 CSV 动态取得所有唯一实例类型，再针对每种类型过滤原始行并用 `length` 计数。因此这里没有把 `micro`、`nano` 或数量写死。当前 CSV 的结果为：

```hcl
instance_count_by_type = {
  "micro" = 2
  "nano"  = 2
}
```

## Task 7：list of maps

继续加入：

```hcl
output "instance_details" {
  value = [
    for row in local.ec2_data : {
      team = row.Team_Name
      type = row.instance_type
    }
  ]
}
```

每个 CSV 行被转换成一个只含 `team` 和 `type` 的对象，外层结果保持 CSV 的行顺序。

## Task 8：map of maps

最后加入：

```hcl
output "map_of_maps" {
  value = {
    for row in local.ec2_data :
    "${row.instance_type}_${row.Region}_${row.Team_Name}" => {
      ami_id        = row.AMI_ID
      instance_type = row.instance_type
      region        = row.Region
      team_name     = row.Team_Name
    }
  }
}
```

花括号形式的 `for` 需要同时产生 `key => value`。这里的 key 动态拼接实例类型、Region 和 Team，value 是该 CSV 行转换成的对象。组合 key 必须唯一；如果 CSV 出现完全相同的组合，Terraform 会提示 duplicate object key，需要先确认题目期望是去重、分组还是修改 key，不能随意覆盖。

## 操作与验证

在 `challenge-7` 目录依次执行：

```bash
terraform fmt
terraform init -backend=false
terraform validate
terraform apply -auto-approve
terraform output
terraform output -json
terraform plan
```

验收结果：

- `validate` 显示配置有效。
- `apply` 显示 `Resources: 0 added, 0 changed, 0 destroyed`，并计算出全部 7 个 output。
- `list_amis` 和 `instance_details` 的顺序与 CSV 一致。
- `unique_team_names` 是无重复且排序后的列表。
- `instance_count_by_type` 中 `micro = 2`、`nano = 2`。
- `map_of_maps` 有 4 个唯一 key，内容与对应 CSV 行一致。
- 再次执行 `plan` 显示 `No changes. Your infrastructure matches the configuration.`

`terraform output -json` 适合检查嵌套数据的实际类型和值。Output 用法参见 [Output values](https://developer.hashicorp.com/terraform/language/values/outputs)。

本题没有资源，因此 `terraform state list` 不应列出资源；执行 `terraform destroy` 也会显示销毁 0 个资源，不会销毁 LocalStack 或 AWS 对象。

## 最终检查

- `main.tf` 与 `ec2.csv` 位于同一题目目录，读取路径使用 `${path.module}`。
- output 名称与题目完全一致，共 7 个。
- 除 Task 5 的筛选条件 `nano` 外，AMI、Region、Team、实例类型集合和数量均来自 CSV。
- `terraform validate` 成功，`terraform output` 与题目参考结果一致。
- 最终 `terraform plan` 为零变更。
- 完成实验后只删除自己启动的容器：

  ```bash
  docker rm -f codex-challenge7-localstack
  ```
