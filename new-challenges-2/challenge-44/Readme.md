# Challenge 44：在 Local Module Release-v1 与 Release-v2 之间切换

这个练习从一个不创建 AWS 资源的可运行基线开始。你会临时制作两个本地 module release，
保持相同 module call label 与核心 resource 地址，再切换 `source`。重点是理解本地路径
不是 registry 语义版本，`terraform init`/`get` 与 provider lockfile 各管理什么。

## 官方考试目标

- **3a**：Manage Terraform, providers, and modules using version constraints
- **4b**：Use a module in configuration
- **4c**：Refactor a module and use module versioning

临时 module 使用官方 AWS `aws_s3_bucket` 与 `aws_s3_object`。兼容
Terraform `>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-44
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

源 TF 只有 caller identity、`terraform_data.module_baseline` 与输出；没有 module call
或 S3 bucket。所有 release 目录都在临时 `work` 内创建。

## Task 1：运行无 Module 的基线

```powershell
New-Item -ItemType Directory .\work
Copy-Item .\challenge-44.tf .\work\main.tf
Set-Location .\work
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output starter_module_baseline
terraform state list
```

state 此时只含 baseline terraform_data 和 caller data。

## Task 2：创建并消费 Release-v1

创建 `modules/release-v1`，其中：

- 声明 AWS provider source；
- 输入为 bucket name 与 release label；
- `aws_s3_bucket.this` 创建 `tfpro-c44-release`；
- tags 含 Challenge/Release；
- 输出 contract version 1、name、ARN、release label。

在 root 添加 `module "release"`，source 指向 v1，并输出 `release_contract`。

```powershell
New-Item -ItemType Directory .\modules\release-v1
New-Item -ItemType File .\modules\release-v1\main.tf
New-Item -ItemType File .\modules\release-v1\variables.tf
New-Item -ItemType File .\modules\release-v1\outputs.tf
terraform fmt -recursive
terraform init
terraform validate
terraform apply -auto-approve
terraform output release_contract
terraform state list
```

预期创建一个 bucket，地址为 `module.release.aws_s3_bucket.this`。

## Task 3：发布 Release-v2 并切换 Source

复制 v1 作为 v2，再在 v2：

- 保持 `aws_s3_bucket.this` 地址与已有 inputs；
- 新增 `aws_s3_object.manifest`，固定 key 为 `release/manifest.json`，内容引用 release label；
- 添加 `ModuleRelease = "v2"` tag；
- contract version 改为 2，并增加 manifest key。

```powershell
Copy-Item .\modules\release-v1 .\modules\release-v2 -Recurse
```

将 root module source 改为 `./modules/release-v2`：

```powershell
terraform fmt -recursive
terraform init -upgrade
terraform plan '-out=v2.tfplan'
terraform show v2.tfplan
```

预期原 bucket 不重建，只新增 manifest object 并更新 tags/output。确认后 apply。

## Task 4：检查本地 Module 的“版本”语义

```powershell
terraform apply v2.tfplan
Remove-Item .\v2.tfplan
terraform output release_contract
Get-Content .\.terraform\modules\modules.json
Select-String -Path .\.terraform.lock.hcl -Pattern 'release-v1|release-v2'
```

`modules.json` 会记录本地 source 路径；provider lockfile 不会记录 local module release。
本地目录名 `release-v2` 只是你维护的约定，不支持 registry module 的 `version` argument。

接着把当前调用与真正的 registry module 版本合同作对照（只审阅，不要把不存在的地址写进
工作副本）：

```hcl
module "release" {
  source  = "app.terraform.io/example/release/aws"
  version = "~> 2.0"

  bucket_name  = "tfpro-c44-release"
  release      = "v2"
}
```

说明 `source` 负责身份，`version` 负责从可用 releases 中选择兼容版本；`~> 2.0` 允许
2.x 的兼容升级但不接受 3.0。Registry module 的选择记录在 `.terraform/modules/modules.json`
及初始化目录中，而不是 provider dependency lockfile。再解释为什么 local path module 不能
靠加一个 `version` argument 获得同样语义。

## Task 5：做一次可逆 Source 切换

把 source 临时切回 v1，运行：

```powershell
terraform init
terraform plan
```

预期 bucket 地址仍相同，但计划删除 v2-only manifest object 并移除 tag；不要 apply。再把 source
恢复到 v2：

```powershell
terraform init
terraform plan
```

应恢复 `No changes`。这说明 source 内容决定差异，目录名本身不会迁移 state。

## Task 6：API/State 验收并删除临时 Releases

```powershell
terraform output release_contract
aws --endpoint-url=http://localhost:4566 s3api head-object --bucket tfpro-c44-release --key release/manifest.json
terraform state list
terraform plan
terraform destroy -auto-approve
Set-Location ..
Remove-Item .\work -Recurse -Force
Get-ChildItem -Force
```

最终 v2 合同、API 与 state 应一致，plan 为 `No changes`。销毁后 bucket 不存在，源目录
只剩两个 starter 文件。

## LocalStack 提醒

- Local module 不会从 registry 下载，也没有 registry version selection。
- 切 source 后仍要运行 init，让 Terraform 刷新 module installation metadata。
- v1/v2 是临时教学目录，清理时不得留在 challenge 目录。
