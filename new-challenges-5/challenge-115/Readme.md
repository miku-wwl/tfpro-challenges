# Challenge 115：Git module 没有 `version` 参数

Registry module 和 Git module 都写在 `module` block 中，但它们的版本选择语法并不相同。本题用一个纯计算
Git module 生成 CIDR，再由 LocalStack S3 保存结果。你会故意把 Registry 的 `version` 写法用到 Git source
上，观察 Terraform 在初始化阶段拒绝配置，然后改用 tag 和完整 commit SHA 正确固定 Git 版本。

## 官方考试目标

- **1a**：初始化工作目录并诊断 module 安装错误
- **3a**：理解 module 版本选择与约束
- **4b**：调用 module 并消费 module outputs
- **4c**：管理 module 版本
- 辅助使用 **2c / 2e**：组织计算结果与结构化 output

考纲依据为 [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。
本题使用 Terraform 1.6 的
[module block 语法](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/syntax)和
[module sources](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)。AWS 部分只使用考试资源清单内的
`aws_s3_bucket` 与 `aws_s3_object`。

## Starter 状态

```powershell
Set-Location .\new-challenges-5\challenge-115
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

git --version
aws --endpoint-url=http://localhost:4566 sts get-caller-identity
```

目录只有 `Readme.md` 与 `challenge-115.tf`。Starter 包含：

- Git source `hashicorp/terraform-cidr-subnets`，以 `ref=v1.0.0` 选择 tag；
- `10.115.0.0/16` 下的 `app` 与 `data` 两个 `/24` 网络；
- LocalStack bucket `tfpro-c115-git-version-boundary`；
- 尚未创建保存 module 结果的 S3 object。

远程 module 首次下载需要访问 GitHub；AWS API 必须指向 LocalStack Ultimate。

## Task 1：部署 tag 固定的 Git module 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c115-baseline.tfplan'
terraform show .\c115-baseline.tfplan
terraform apply .\c115-baseline.tfplan
Remove-Item -LiteralPath .\c115-baseline.tfplan

terraform output starter_network_contract
terraform state list
terraform plan
```

预期只创建一个 S3 bucket；CIDR module 本身没有 provider 或 resource，因此不会单独出现在 state list 中。
output 中 `app` 与 `data` 应分别得到不重叠的 `/24`，最终 plan 为 `No changes`。

检查远端 bucket 与 module 安装记录：

```powershell
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c115-git-version-boundary
Get-Content -Raw .\.terraform\modules\modules.json
```

## Task 2：错误地给 Git module 添加 `version`

在 `module "network"` 中临时添加：

```hcl
version = "1.0.0"
```

保留原来的 Git source，然后运行：

```powershell
terraform init
terraform validate
```

初始化或验证应失败，错误会指出 module `version` 只适用于 Registry source，或者当前 source 不是有效的
Registry module address。关键不是背诵错误原文，而是识别下面的语法边界：

```text
Registry source -> version = "..." 约束
Git source      -> URL 查询参数 ref=...
```

安装失败不会修改现有 state 或 LocalStack bucket。现在删除刚才添加的 `version`，不要继续 apply 错误配置。

## Task 3：把 tag 改为完整 commit SHA

`v1.0.0` 对应的完整 commit SHA 是：

```text
52ca061aaea2e8f58c91ac03ca1fae45e44c28bf
```

只修改 source 的 `ref`：

```hcl
source = "git::https://github.com/hashicorp/terraform-cidr-subnets.git?ref=52ca061aaea2e8f58c91ac03ca1fae45e44c28bf"
```

先证明 source 变化需要重新初始化，再正确安装：

```powershell
terraform plan
terraform init -upgrade
terraform validate
terraform plan '-out=c115-sha.tfplan'
terraform show .\c115-sha.tfplan
```

第一个 plan 应要求重新运行 init；初始化后保存的 plan 应为 `No changes`，因为 tag 和 SHA 对应同一份
module 代码。删除空计划：

```powershell
Remove-Item -LiteralPath .\c115-sha.tfplan
```

## Task 4：让 AWS 资源消费 module output

创建 `aws_s3_object.network_contract`：

- bucket 引用 `aws_s3_bucket.evidence.id`；
- key 为 `network.json`；
- `content_type` 为 `application/json`；
- content 使用 `jsonencode`，至少包含 `source_kind = "git"`、完整 `ref` 和
  `module.network.network_cidr_blocks`。

不要复制 CIDR 字符串；S3 object 必须真正依赖 module output。

```powershell
terraform fmt
terraform validate
terraform plan '-out=c115-object.tfplan'
terraform show .\c115-object.tfplan
terraform apply .\c115-object.tfplan
Remove-Item -LiteralPath .\c115-object.tfplan
```

预期只新增一个 `aws_s3_object.network_contract`，不会替换 bucket。

## Task 5：检查 cache、lockfile、state 与 API 的职责

```powershell
Get-Content -Raw .\.terraform\modules\modules.json
Get-Content -Raw .\.terraform.lock.hcl
terraform state list
terraform state show aws_s3_object.network_contract

aws --endpoint-url=http://localhost:4566 s3api get-object `
  --bucket tfpro-c115-git-version-boundary `
  --key network.json `
  .\c115-downloaded.json
Get-Content -Raw .\c115-downloaded.json
Remove-Item -LiteralPath .\c115-downloaded.json

terraform plan
```

应能区分四类信息：module source 在配置和 `modules.json` 中；module 文件位于 `.terraform/modules`；
provider selection 在 lockfile；AWS bucket/object 在 state 与 LocalStack API。lockfile **不会**记录 Git module
commit。最后一个 plan 必须为 `No changes`。

## Task 6：销毁、恢复 tag starter 并清除运行产物

先在当前完整 SHA 配置下销毁：

```powershell
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c115-git-version-boundary
```

state 应为空；`head-bucket` 应报告不存在。删除你添加的 S3 object block，并把 source 恢复为：

```hcl
source = "git::https://github.com/hashicorp/terraform-cidr-subnets.git?ref=v1.0.0"
```

最后清理：

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

目录最终只能有 `Readme.md` 与恢复原样的 `challenge-115.tf`。

## 边界提醒

- Git `ref` 可以是 branch、tag 或 commit SHA；它不是 Terraform version constraint。
- `version = "~> 1.0"` 之类的选择逻辑只适用于 Registry module。
- `.terraform.lock.hcl` 锁 provider，不锁 remote module；不要从 lockfile 推断 Git module 版本。
- 本题不涉及发布 Registry module、自建 Registry protocol 或 Git 身份认证。
