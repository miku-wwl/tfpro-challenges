# Challenge 84：Optional/Null Compute Contract 与变量优先级

这个练习把“没有提供”“显式为 null”和“有默认值”拆开观察。Starter 已经能用默认对象
创建 EC2；你会添加 validation 与规范化输出，再只用环境变量和 `-var` 比较输入优先级。
不创建或提交 `.tfvars`，所以题目结束时目录仍然只有 README 与 `.tf`。

## 官方考试目标

- **2a**：Use language features to validate configuration
- **2c**：Compute and interpolate data using HCL functions
- **2e**：Configure input variables and outputs, including complex types
- **3c**：Use the Terraform workflow in automation

使用官方 AWS 学习资源中的 `data.aws_ami`、`data.aws_subnet` 与 `aws_instance`。语法边界
固定为 Terraform `~> 1.6.0`。

## 先理解这份类型

`compute` 中有两类 optional 属性：

- `instance_type`、`availability_zone`、`tags` 带 optional default；省略或显式传 null 时，
  Terraform 会使用该 default；
- `user_data = optional(string)` 没有 default；省略时保持 null，并让 provider 使用其默认
  行为。

变量值的本题优先级为：显式 `-var` 高于 `TF_VAR_compute`，两者都没有时使用 variable
default。

## Task 1：用 Variable Default 部署基线

```powershell
Set-Location .\new-challenges-4\challenge-84
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=default.tfplan'
terraform apply default.tfplan
terraform output starter_instance
Remove-Item -LiteralPath .\default.tfplan
```

预期创建 1 台名为 `tfpro-c84-default`、类型为 `t3.micro` 的 LocalStack instance。

## Task 2：在输入边界加入业务 Validation

给 `variable "compute"` 添加 validation，至少保证：

1. name 只含字母、数字和连字符，长度 3～40；
2. instance type 只能是 `t3.micro` 或 `t3.small`；
3. availability zone 必须以 `us-east-1` 开头。

先验证正常路径：

```powershell
terraform fmt
terraform validate
terraform plan
```

再验证失败路径：

```powershell
terraform plan '-var=compute={name=\"bad_name\",instance_type=\"m5.large\",availability_zone=\"eu-west-1a\",user_data=null,tags={}}'
```

预期失败于 variable validation，并且不会调用 EC2 API修改实例。

## Task 3：计算 Effective Compute 并输出 Contract

这一步分为两层，不要把 `local` 和 `output` 当成同一个东西：

1. 添加 `local.effective_compute`，只负责整理最终生效的配置：
   - name、instance type、availability zone；
   - 合并后的 tags；
   - `user_data_is_null = var.compute.user_data == null`。
2. 添加 `output "compute_contract"`，引用上述 local，并补充资源运行信息：
   - instance ID；
   - AMI ID；
   - Subnet ID；

原始输入仍通过 `var.compute` 查看；`local.effective_compute` 是中间计算结果，
`compute_contract` 才是对外展示的最终合同。

```powershell
terraform apply -auto-approve
terraform output compute_contract
terraform plan
```

默认路径下 `user_data_is_null` 应为 `true`，plan 应为 `No changes`。

> **Note（☆）**：本题不实现可选的 `user-data hash` 输出。
> `compute_contract` 不输出 user-data 明文，也不输出其 hash。

## Task 4：让 `TF_VAR_compute` 覆盖 Variable Default

在当前 PowerShell session 中设置完整的 object 值，但省略带 default 的 optional 属性：

```powershell
$env:TF_VAR_compute = '{ name = "tfpro-c84-env", tags = { Source = "environment" } }'
terraform plan
terraform console
```

在 console 中检查：

```hcl
var.compute
local.effective_compute
```

预期 name/tags 来自环境变量，而 instance type 与可用区由 optional defaults 补齐；
user_data 仍为 null。退出 console。本 task 只 plan，不 apply。

## Task 5：用 `-var` 覆盖环境变量并观察 Explicit Null

保留 `TF_VAR_compute`，执行：

```powershell
terraform plan '-var=compute={name=\"tfpro-c84-cli\",instance_type=null,availability_zone=null,user_data=null,tags={Source=\"cli\"}}'
```

预期：

- `-var` 整体优先于 `TF_VAR_compute`；
- name 为 `tfpro-c84-cli`，Source 为 `cli`；
- 显式为 null 的 instance type/AZ 使用各自 optional default；
- 没有 default 的 user_data 仍为 null。

再传入非 null user-data，保存计划但不要 apply：

```powershell
terraform plan `
  '-var=compute={name=\"tfpro-c84-cli\",instance_type=\"t3.small\",availability_zone=\"us-east-1a\",user_data=\"release=v2\",tags={Source=\"cli\"}}' `
  '-out=cli.tfplan'
terraform show cli.tfplan
Remove-Item -LiteralPath .\cli.tfplan
```

预期计划使用 CLI 值，并清楚显示 instance type/user-data 变更。

## Task 6：清除环境输入、验收默认路径并清理

```powershell
Remove-Item Env:\TF_VAR_compute
terraform plan
terraform output compute_contract

$instanceId = (terraform output -json compute_contract | ConvertFrom-Json).instance_id
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $instanceId `
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,Subnet:SubnetId,Tags:Tags}'

terraform destroy -auto-approve
```

因为 Task 4/5 只生成 plan，清除环境变量后应重新得到 `No changes`。销毁并删除所有运行
产物，源目录只保留 `Readme.md` 和 `challenge-84.tf`。

## 常见陷阱

- PowerShell 中给复杂 `-var` 使用单引号包住整个 `-var=...` 参数，内部 HCL 字符串仍用
  双引号。
- `TF_VAR_compute` 覆盖的是整个 object，不会和 variable default 做任意深度 merge；只是
  optional 属性自己的 default 会补齐。
- LocalStack 不执行真实 user-data。这里只检查 plan、state 与 API metadata。
- 结束前一定删除 `TF_VAR_compute`，否则它会影响后续练习。

## Note（☆）：Task 4/5 中较少见的知识点

- `TF_VAR_<name>` 可以从环境变量提供变量值；命令行 `-var` 的优先级高于它。
- `optional(type, default)`：属性为 `null` 或省略时，使用 optional 的默认值；没有默认值的 optional 属性仍为 `null`。
- 变量整体由 `-var` 覆盖时，不是只覆盖其中一个属性；整个 object 使用命令行传入的值。
- `terraform plan -out=tfplan` 会保存计划，`terraform show tfplan` 用于查看保存的计划；只保存或查看不会 apply。
- `user_data` 等敏感或可能泄露内容的值，不应作为 `for_each` key，也不应直接输出；需要时只输出 hash。
