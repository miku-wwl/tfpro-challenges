# Challenge 46：从 Requirements Graph 追到 Provider Plugin Schema

这道题从一个可运行的 S3 baseline 出发，沿着 `required_providers`、dependency lock file、
安装目录和 provider schema 逐层追踪 Terraform 如何发现并启动 AWS provider。重点不是记住
缓存路径，而是能把“配置要求、版本选择、插件进程、资源 schema”四层证据连起来。

## 官方考试目标

- **1a**：Initialize a configuration using `terraform init` and its options
- **5a**：Understand Terraform's plugin-based architecture
- **5b**：Configure providers, including aliasing, versioning, sourcing, and managing upgrades

范围依据：[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。
本题只使用 Terraform 1.6 已有命令；AWS provider 固定从已验证的 `5.80.0` 起步。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-46
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
~~~

目录只有 `Readme.md` 与 `challenge-46.tf`。配置声明一个 provider requirement、一个
provider configuration、一个 caller identity 查询和一个尚未部署的 bucket。开始前确认
LocalStack 的 S3、STS 可用，目录中没有 lockfile、state 或 `.terraform`。

## Task 1：初始化并区分“要求”与“选择”

~~~powershell
terraform init
terraform providers
Get-Content .\.terraform.lock.hcl
~~~

`terraform providers` 应显示 root module 要求 `registry.terraform.io/hashicorp/aws`；
lockfile 则记录本次实际选择的 `5.80.0` 与校验和。说明为什么 provider block 中的
`region` 不是 provider 的安装要求，也不会出现在 requirements graph 中。

## Task 2：找到安装包但不要执行或修改它

~~~powershell
Get-ChildItem -Recurse .\.terraform\providers
terraform version
~~~

确认目录层级包含 source address、版本、平台和一个 provider 可执行文件。Terraform Core
通过插件协议启动它；`.tf` 配置不会被复制进 provider 二进制。不要手工编辑、替换或运行
安装包。

## Task 3：从机器可读 Schema 核对资源合同

~~~powershell
terraform providers schema -json |
  Set-Content -Encoding utf8 .\provider-schema.json

$schema = Get-Content -Raw .\provider-schema.json | ConvertFrom-Json
$aws = $schema.provider_schemas.'registry.terraform.io/hashicorp/aws'
$aws.resource_schemas.aws_s3_bucket.block.attributes.bucket
~~~

输出应能区分 `bucket` 的 type，以及它是 optional、required 还是 computed。再检查
`force_destroy` 和 data source `aws_caller_identity`。这是 provider schema，不是远端
AWS API 返回值；此命令本身不创建 bucket。

## Task 4：证明 Provider 负责运行期，Core 负责计划编排

~~~powershell
terraform validate
terraform plan '-out=c46.tfplan'
terraform show c46.tfplan
terraform apply c46.tfplan
terraform output starter_contract
~~~

预期只创建一个 S3 bucket；account ID 来自 LocalStack STS。用 API 独立核对：

~~~powershell
aws --endpoint-url=http://localhost:4566 s3api head-bucket --bucket tfpro-c46-plugin-probe
~~~

解释哪一步必须与 provider plugin 通信，哪一步只是 Core 读取已生成的计划。

## Task 5：在隔离副本观察只读 Lockfile

把两份源文件复制到一个新建的系统临时目录，在副本中先复制当前 lockfile，再运行：

~~~powershell
terraform init -lockfile=readonly
terraform providers
~~~

预期沿用 `5.80.0` 且不改 lockfile。随后在副本中把版本约束临时改成不包含 `5.80.0` 的
范围，再次运行同一命令；预期 init 拒绝选择新版本，而不是静默改写 lockfile。删除该副本，
不要把实验性约束带回 starter。

## Task 6：最终验收与清理

~~~powershell
terraform plan
terraform state list
terraform destroy -auto-approve
Remove-Item -Force .\c46.tfplan, .\provider-schema.json -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
Get-ChildItem -Force
~~~

销毁前 plan 应为 `No changes`；销毁后 state 与 LocalStack bucket 都应消失。最终目录必须
恢复为两份源文件。递归删除前只对本题目录内字面量 `.terraform` 路径执行。

## Terraform 1.6 与 LocalStack 边界

- 考试测试 Terraform 1.6；不要把当前较新 CLI 的新增选项写进答案。
- Provider plugin 仍来自 HashiCorp Registry；LocalStack 只替代 AWS API endpoint。
- Provider 版本不是考试固定值，`5.80.0` 只是本仓已验证的练习基线。
