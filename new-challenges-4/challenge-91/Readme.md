# Challenge 91：Provider Requirements Graph 与 Schema Inspection

这道题不从“改资源”开始，而是先读懂 Terraform 如何解析 provider。Starter 可以正常
部署，但 child module 没有显式声明 `required_providers`，Terraform 只能依靠历史兼容
规则推断它使用 `hashicorp/aws`。你会先观察推断结果，再把 provider source、版本和
Terraform CLI 边界写成明确的模块合同，并用一次可控的版本冲突理解初始化失败。

## 考纲定位

- **1a**：Initialize a configuration using `terraform init` and its options
- **3a**：Manage the Terraform binary, providers, and modules using version constraints
- **5a**：Understand Terraform's plugin-based architecture
- **5d**：Troubleshoot provider errors

官方范围：[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。

## 起始结构

```text
challenge-91/
├── Readme.md
├── challenge-91.tf
└── modules/
    └── release/
        └── main.tf
```

- Root module 已固定 Terraform `~> 1.6.0` 与 AWS provider `5.80.0`。
- Root provider 只连接本题实际使用的 LocalStack S3 endpoint。
- Child module 管理一个 bucket，但 starter 故意没有 `terraform.required_providers`。
- 这不是资源故障：Task 1 的 baseline 必须成功。

## 开始前

工作目录：

```powershell
Set-Location .\new-challenges-4\challenge-91
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
```

请使用 Terraform 1.6.x。目录中不应存在 `.terraform`、lockfile、state 或 plan 文件。

## Task 1：部署依靠隐式 Provider 推断的基线

工作目录：`new-challenges-4/challenge-91`

```powershell
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply baseline.tfplan
terraform state list
terraform output release_contract
```

预期结果：

- 创建 `tfpro-c91-release`。
- state 地址是 `module.release.aws_s3_bucket.this`。
- output 同时包含 bucket name 与 ARN。

此时 child module 可以工作，不等于它的依赖合同已经完整。

## Task 2：读取 Requirements Graph 与 Provider Schema

仍在 challenge 根目录：

```powershell
terraform providers
```

Root 应显示 `registry.terraform.io/hashicorp/aws 5.80.0`；child 路径也会显示 AWS
provider，但它来自 Terraform 的隐式推断，而不是 child 自己声明的合同。

不要把完整 schema 写进仓库。直接在内存中检查：

```powershell
$schema = terraform providers schema -json | ConvertFrom-Json
$awsSchema = $schema.provider_schemas.'registry.terraform.io/hashicorp/aws'
$awsSchema.provider.block.attributes.region
$awsSchema.resource_schemas.PSObject.Properties.Name -contains 'aws_s3_bucket'
```

最后一行必须是 `True`。这份 JSON 来自已安装的 provider plugin，不是 AWS API。

## Task 3：给 Child Module 建立显式依赖合同

编辑 `modules/release/main.tf`，在文件顶部添加 `terraform` block：

- `required_providers.aws.source = "hashicorp/aws"`；
- `required_providers.aws.version = "5.80.0"`。

Child module 只能声明 requirement；不要在 child 内添加 `provider "aws"`，也不要在
child 中写 credentials 或 endpoint。

```powershell
terraform init
terraform providers
terraform validate
terraform plan
```

预期结果：requirements graph 现在能从源码解释 root 与 child 的约束，plan 为
`No changes`。添加依赖元数据不得替换 bucket。

## Task 4：观察不相交版本约束的预期失败

这个失败只用于诊断。临时把 child 的 AWS provider version 改为 `>= 6.0.0`，root
仍保持 `5.80.0`，然后执行：

```powershell
terraform init -upgrade
```

预期结果：初始化失败，并明确指出无法同时满足 `5.80.0` 与 `>= 6.0.0`。这不是
LocalStack endpoint、credentials 或 S3 故障；provider 甚至还没有进入调用 AWS API 的阶段。

观察后立即把 child 版本恢复为 `5.80.0`：

```powershell
terraform init -upgrade
terraform validate
terraform plan
```

三个命令必须恢复成功，最终 plan 为零变更。

## Task 5：最终验收

```powershell
terraform fmt -check -recursive
terraform validate
terraform providers
terraform state show module.release.aws_s3_bucket.this
terraform output -json release_contract
terraform plan -detailed-exitcode
```

必须满足：

- 最后一个命令退出码为 `0`，不是表示有变更的 `2`。
- root 与 child 都显式约束 AWS `5.80.0`。
- child 没有 provider configuration。
- bucket 仍是 Task 1 创建的同一个物理对象。

## 清理

```powershell
terraform destroy -auto-approve
Remove-Item -Force .\baseline.tfplan -ErrorAction SilentlyContinue
```

确认 `tfpro-c91-release` 已删除。练习生成的 `.terraform`、lockfile、state 和 plan 都是
本地运行产物，不得提交。

## Terraform 1.6 边界

本题只使用 Terraform 1.6 已有的 provider requirements、dependency lockfile、
`terraform providers` 与 `terraform providers schema -json`。不要引入 provider mocks、
ephemeral values、write-only arguments 或 Terraform 1.7+ 功能。
