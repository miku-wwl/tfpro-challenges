# Challenge 101：固定 Registry Module，并把 CIDR 合同发布到 S3

本题从一个真实的 LocalStack S3 bucket 开始。你会添加纯计算 Registry module
`hashicorp/subnets/cidr`，用精确版本固定其行为，再把模块 output 编码成 JSON
并交给 `aws_s3_object` 发布。

## 官方考试目标

- **1a**：Initialize a configuration using `terraform init` and its options
- **2c / 2e**：使用表达式计算数据，并配置复杂 outputs
- **3a**：使用版本约束管理 Terraform、provider 与 modules
- **4b**：调用并使用 Registry module

参考 [Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
和 [Terraform 1.6 Module Sources](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)。
本题只创建考纲白名单中的 `aws_s3_bucket` 与 `aws_s3_object`。

## 开始之前

启动 LocalStack Ultimate，并确认当前机器可以访问 Terraform Registry。LocalStack
负责 AWS runtime；`terraform init` 下载 Registry module 时仍需要网络：

```powershell
Set-Location .\new-challenges-5\challenge-101
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

aws --endpoint-url=http://localhost:4566 s3api list-buckets
```

## Starter 状态

`challenge-101.tf` 目前只有：

- 固定为 `5.80.0` 的 AWS provider；
- 指向 LocalStack 的 S3/STS endpoints；
- bucket `tfpro-c101-contract`；
- `starter_bucket` output。

还没有 module、local value 或 S3 object。目录只有 `Readme.md` 与
`challenge-101.tf`，不要添加脚本或其他 Terraform 文件。

## Task 1：部署 S3 基线

先保存并审阅基线计划，再应用同一个文件：

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c101-baseline.tfplan'
terraform show .\c101-baseline.tfplan
terraform apply .\c101-baseline.tfplan
Remove-Item -LiteralPath .\c101-baseline.tfplan

terraform output starter_bucket
terraform state show aws_s3_bucket.contract
```

预期只创建一个 bucket。用 API 核对名称：

```powershell
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c101-contract
```

成功命令没有 response body；退出码应为 `0`。

## Task 2：添加精确版本的 CIDR Module

新增 module block，label 使用 `network_plan`，并严格满足：

- `source = "hashicorp/subnets/cidr"`；
- `version = "1.0.0"`，不能写范围约束；
- `base_cidr_block = "10.101.0.0/16"`；
- `networks` 按顺序包含 `public-a`、`public-b`、`private-a`、`private-b`；
- 每项的 `new_bits` 都是 `8`。

`new_bits = 8` 表示在 `/16` 后追加 8 位，因此结果是 `/24`；它不是最终前缀长度。
加入 module 后必须重新初始化：

```powershell
terraform init
terraform fmt
terraform validate
```

init 输出应明确安装 `hashicorp/subnets/cidr 1.0.0`。检查 Terraform 保存的
module 安装记录：

```powershell
$modules = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$modules.Modules |
  Where-Object Key -eq "network_plan" |
  Select-Object Key,Source,Version,Dir
```

`Version` 必须是 `1.0.0`。

## Task 3：先验证纯计算结果

在还没有创建 S3 object 时，使用 console 检查 module outputs：

```powershell
terraform console
```

依次求值：

```hcl
module.network_plan.base_cidr_block
module.network_plan.network_cidr_blocks
module.network_plan.networks
```

预期名称到 CIDR 的映射为：

- `public-a  = 10.101.0.0/24`；
- `public-b  = 10.101.1.0/24`；
- `private-a = 10.101.2.0/24`；
- `private-b = 10.101.3.0/24`。

退出 console 后运行 `terraform plan`。此时 module 本身不创建资源，所以计划仍应
`No changes`。

## Task 4：把 Module Output 编译成 S3 合同

新增 `local.network_contract`，合同必须包含：

- `schema_version = 1`；
- `base_cidr_block`，引用 module output；
- `network_cidr_blocks`，引用 module output。

再新增 `aws_s3_object.network_contract`：

- bucket 引用 `aws_s3_bucket.contract.id`；
- key 固定为 `contracts/network-plan-v1.json`；
- `content_type = "application/json"`；
- content 使用 `jsonencode(local.network_contract)`；
- tags 包含 `Challenge = "101"` 和 `ManagedBy = "Terraform"`。

最后新增 `network_contract` output，直接发布同一个 local value。不要在 resource
和 output 中复制两份合同。

```powershell
terraform fmt
terraform validate
terraform plan '-out=c101-contract.tfplan'
terraform show .\c101-contract.tfplan
terraform apply .\c101-contract.tfplan
Remove-Item -LiteralPath .\c101-contract.tfplan
```

计划只应新增一个 S3 object；bucket 不应替换。

## Task 5：区分 Module 安装记录与 Provider Lock

Registry module 的选定版本记录在工作目录的 module cache 中，但
`.terraform.lock.hcl` 只锁 provider，不锁 remote module。交叉检查：

```powershell
$modules = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$modules.Modules |
  Where-Object Key -eq "network_plan" |
  Select-Object Key,Source,Version

Select-String -Path .\.terraform.lock.hcl -Pattern 'hashicorp/subnets'
terraform providers
terraform plan
```

module 记录应显示 `1.0.0`；`Select-String` 不应找到 module 条目；provider
仍应是 `hashicorp/aws 5.80.0`。最终 plan 必须 `No changes`。

## Task 6：从 Output、State 与 S3 API 验收并清理

下载并解析 JSON，比较字段值而不是 JSON 文本空白或 key 顺序：

```powershell
$bucket = (terraform output -json starter_bucket | ConvertFrom-Json).name
$download = ".\network-plan-v1.json"

aws --endpoint-url=http://localhost:4566 s3api get-object `
  --bucket $bucket `
  --key contracts/network-plan-v1.json `
  $download

$remoteContract = Get-Content -Raw $download | ConvertFrom-Json
$remoteContract
terraform output network_contract
terraform state list
```

远端 JSON 与 Terraform output 都应包含四个预期 `/24`。`terraform state list`
只列 bucket 和 object；纯计算 module 没有 resource address。

保存 bucket 名后销毁：

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api list-buckets `
  --query "Buckets[?Name=='$bucket'].Name"
```

state 与查询结果都应为空。把 `challenge-101.tf` 恢复为 starter 内容，再清理运行产物：

```powershell
Remove-Item -Force -LiteralPath .\network-plan-v1.json -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能剩 `Readme.md` 与 `challenge-101.tf`。

## LocalStack 提醒

- `hashicorp/subnets/cidr` 是纯计算 module；只有 S3 资源会调用 LocalStack。
- 本题固定 module `1.0.0` 是为了可重复安装，不要改用 Git source 或浮动版本。
- `jsonencode` 生成压缩 JSON；API 验收应解析字段，不应比较格式。
