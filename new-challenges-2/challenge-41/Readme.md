# Challenge 41：把单体 S3 Release 提取为 Child Module

这个练习从一个已经部署过的单体 S3 release 开始。你会在临时工作副本中把 bucket 与
manifest object 移入 child module，先观察缺少 state 映射时的 destroy/create，再用
`moved` blocks 把旧地址迁到 module 地址，要求最终重构计划为零资源变更。

## 官方考试目标

- **4a**：Create a module
- **4d**：Refactor an existing configuration into modules
- **1e**：Manage resource state, including importing resources and reconciling resource drift

使用官方 AWS `aws_s3_bucket`、`aws_s3_object` 和 Terraform `moved` block。
兼容 Terraform `>= 1.6.0, < 2.0.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-41
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

源目录只有 `Readme.md` 和 `challenge-41.tf`。TF 是可 apply 的单体配置，管理
`tfpro-c41-release` bucket 与固定 key 的 manifest object；没有 module、module call 或 moved block。

## Task 1：在临时副本部署单体基线

```powershell
New-Item -ItemType Directory -Path .\work
Copy-Item -LiteralPath .\challenge-41.tf -Destination .\work\main.tf
Set-Location .\work

terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform state list
terraform output release_contract
```

state 应使用两个根地址：`aws_s3_bucket.release` 与
`aws_s3_object.manifest`。

## Task 2：创建 Release Child Module

```powershell
New-Item -ItemType Directory -Path .\modules\release
New-Item -ItemType File -Path .\modules\release\main.tf
New-Item -ItemType File -Path .\modules\release\variables.tf
New-Item -ItemType File -Path .\modules\release\outputs.tf
```

在临时 module 中：

- 声明所需 AWS provider source；
- 接收一个类型化 release 对象，包含 bucket name、release label、force_destroy；
- 把两个 resource 从 root 移入 module，资源本地名称保持 `release`；
- 输出 bucket name、ARN、release 与 manifest key。

根模块改为调用 `module "release"`，并让 root output 从 module 读取。暂时不要添加
`moved` block。

## Task 3：先审阅错误迁移，再添加 Moved Blocks

```powershell
terraform fmt -recursive
terraform init
terraform validate
terraform plan '-out=without-moves.tfplan'
terraform show without-moves.tfplan
Remove-Item -LiteralPath .\without-moves.tfplan
```

预期 Terraform 想销毁两个根资源并在 `module.release` 创建两个资源。不要 apply。

在 root 添加两条 moved block，精确映射：

- `aws_s3_bucket.release` 到 `module.release.aws_s3_bucket.release`；
- `aws_s3_object.manifest` 到 `module.release.aws_s3_object.manifest`。

```powershell
terraform plan '-out=refactor.tfplan'
terraform show refactor.tfplan
```

现在必须为零资源 destroy/create；若不是，先修正 module 参数与默认值。

## Task 4：应用地址迁移并检查 State

```powershell
terraform apply refactor.tfplan
Remove-Item -LiteralPath .\refactor.tfplan
terraform state list
terraform plan
```

state 应只包含两个 `module.release...` 地址，plan 为 `No changes`。AWS bucket ID 没有变化。

## Task 5：只通过 Module Interface 发布 V2

把根 module 输入中的 release label 从 `v1` 改为 `v2`，不要直接编辑 child resource：

```powershell
terraform plan '-out=v2.tfplan'
terraform show v2.tfplan
terraform apply v2.tfplan
Remove-Item -LiteralPath .\v2.tfplan
terraform output release_contract
terraform plan
```

预期只更新 bucket tag、manifest 内容与输出，不替换 bucket，最终 `No changes`。

## Task 6：State/API 双向验收并恢复两文件 Starter

```powershell
$contract = terraform output -json release_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket $contract.name
aws --endpoint-url=http://localhost:4566 s3api head-object --bucket $contract.name --key $contract.manifest_key
terraform state list
terraform destroy -auto-approve
Set-Location ..
Remove-Item -LiteralPath .\work -Recurse -Force
Get-ChildItem -Force
```

API 与 module output 应一致；销毁后 bucket 查询应失败。源目录最终只能显示
`Readme.md` 和 `challenge-41.tf`。

## LocalStack 提醒

- Moved block 只改变 Terraform 地址，不调用 S3 rename API。
- LocalStack object metadata 可能简化，但 bucket 名、manifest key 和 state 地址必须精确。
- 所有 module 文件都在 `work` 中临时创建，不能复制回最终 starter 目录。
