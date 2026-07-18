# Challenge 25：为 S3 发布链添加三层 lifecycle 护栏

一个发布桶既允许值班人员临时调整运行标签，又必须防止误删；当发布修订号变化时，固定 key
的 marker object 还必须被明确替换。你将把 `ignore_changes`、`prevent_destroy` 和
`replace_triggered_by` 分别放到职责正确的资源上，并用失败计划和替换计划证明它们生效。

## 官方考试目标

- **1d**：Destroy resources using `terraform destroy` and its options
- **2d**：Use meta-arguments in configuration
- 辅助使用 **1b / 1c**：审阅并应用 lifecycle 导致的计划

本题使用 `aws_s3_bucket`、`aws_s3_object` 和 core `terraform_data`。配置兼容 Terraform
`>= 1.6.0, < 2.0.0`，不使用较新版本的 action、ephemeral 或 S3 lockfile 功能。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-25
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 是可运行但尚无 lifecycle 护栏的发布链：

- `terraform_data.release` 以 `release_version` 作为替换触发值；
- bucket `tfpro-c25-guarded` 带 `OperationalMode = "managed"`；
- `release-marker.txt` 是固定 key 的 S3 object；
- 任何资源都还没有 `lifecycle` block。

目录开始时只能有 `Readme.md` 和 `challenge-25.tf`。

## Task 1：部署无护栏基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply .\baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
terraform output -json guardrail_baseline | ConvertFrom-Json
terraform plan
```

应创建 3 个 state 对象，发布版本为 `v1`，随后 plan 为 `No changes`。

## Task 2：只忽略明确授权的运行标签

先在 API 侧把 `OperationalMode` 改成 `manual`，同时保留其余受管标签：

```powershell
aws --endpoint-url=http://localhost:4566 s3api put-bucket-tagging `
  --bucket tfpro-c25-guarded `
  --tagging 'TagSet=[{Key=Name,Value=tfpro-c25-guarded},{Key=Challenge,Value=25},{Key=OperationalMode,Value=manual}]'
terraform plan
```

普通 plan 应准备把该键改回 `managed`。现在只给 bucket 添加 lifecycle 规则，忽略
`tags` map 中的 `OperationalMode` 元素；不能忽略整个 `tags` 属性。

```powershell
terraform fmt
terraform validate
terraform plan
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c25-guarded
```

plan 应变为 `No changes`，API 仍保留 `manual`。这证明 Terraform 只放弃了该元素的更新权。

## Task 3：让误销毁在计划阶段失败

扩展 bucket 的同一个 lifecycle block，启用 `prevent_destroy`。不要创建第二个 lifecycle
block，也不要把保护放到 marker object 上。

```powershell
terraform fmt
terraform validate
terraform plan -destroy
```

计划必须失败，并明确指出 `aws_s3_bucket.guarded` 启用了 `prevent_destroy`。这是预期的护栏
失败，不要通过删除 state 或手工删除 bucket 绕过它。

## Task 4：让发布修订触发 marker 替换

给 `aws_s3_object.marker` 添加 lifecycle，使 `terraform_data.release` 的 replacement 触发
marker replacement。然后把 `release_version` 默认值从 `v1` 改为 `v2`；不要改 marker 的
key 或 content 来制造替换。

```powershell
terraform fmt
terraform validate
terraform plan '-out=release-v2.tfplan'
terraform show -no-color .\release-v2.tfplan
```

计划应同时显示 `terraform_data.release` 和 `aws_s3_object.marker` replacement，bucket 不应
被替换。审阅后应用同一份计划：

```powershell
terraform apply .\release-v2.tfplan
Remove-Item -LiteralPath .\release-v2.tfplan
terraform output -json guardrail_baseline | ConvertFrom-Json
```

输出中的发布版本应为 `v2`。

## Task 5：联合验证三个护栏

```powershell
terraform plan
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c25-guarded `
  --key release-marker.txt
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c25-guarded
terraform plan -destroy
```

普通 plan 应为 `No changes`；marker 存在；运行标签仍为 `manual`；destroy plan 仍因 bucket
护栏失败。不要为了让最后一条命令成功而提前移除保护。

## Task 6：显式解除销毁保护后清理

清理是经过审阅的配置变更。只移除 bucket lifecycle 中的 `prevent_destroy`，保留另外两个
规则，然后执行：

```powershell
terraform fmt
terraform validate
terraform plan -destroy '-out=cleanup.tfplan'
terraform show -no-color .\cleanup.tfplan
terraform apply .\cleanup.tfplan
Remove-Item -LiteralPath .\cleanup.tfplan
terraform state list
```

state 应为空。最后删除运行产物：

```powershell
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate, .\terraform.tfstate.backup `
  -ErrorAction SilentlyContinue
Get-ChildItem -File -Filter '*.tfplan' | Remove-Item -Force
Get-ChildItem -Force | Select-Object Name
```

目录最终只能包含 `Readme.md` 和 `challenge-25.tf`。

## LocalStack 提醒

- `prevent_destroy` 是 Terraform 配置护栏，不能阻止有权限的人直接调用 AWS API。
- LocalStack 可能为同 key object 返回实现相关的 ETag；本题只验证替换计划与对象存在。
- `create_before_destroy` 不适合证明固定 S3 key 的双对象并存，因此本题选择
  `replace_triggered_by` 保留清晰的 Terraform 语义。
