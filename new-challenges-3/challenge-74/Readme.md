# Challenge 74：无脚本的非交互 Saved Plan 发布门禁

这一题用纯 Terraform CLI 模拟自动化发布：禁止交互式补变量，用 `-detailed-exitcode` 区分错误、无变更和有变更，把 plan 保存成制品，审阅后应用**同一份** plan。

本题不需要脚本、tfvars 或 backend 配置文件。`release-v1.tfplan`、`release-v2.tfplan` 只在练习过程中临时生成，不能作为 starter 文件保留。

## 开始前检查

在 `new-challenges-3/challenge-74` 目录执行：

```powershell
terraform version
docker ps
aws --version
Invoke-RestMethod http://localhost:4566/_localstack/health
```

`release` 是没有 default 的必填变量，因此自动化命令必须显式提供它。

## 任务

### Task 1：完成不依赖输入值的静态检查

```powershell
terraform fmt -check
terraform init
terraform validate
```

`validate` 应成功，因为它检查配置结构与类型，不需要为每个 root input variable 提供运行值。

### Task 2：观察非交互缺参的预期失败

```powershell
terraform plan -input=false
```

这是本题的**预期失败**：命令必须报告 required variable `release` 没有值，并直接退出。不要给变量添加 default，也不要移除 `-input=false`；自动化环境不能等待人工输入。

### Task 3：生成并审阅 v1 Saved Plan

```powershell
terraform plan -input=false -detailed-exitcode `
  -out=release-v1.tfplan `
  -var='release=v1'
$LASTEXITCODE
```

首次计划有资源要创建，因此 `$LASTEXITCODE` 必须是 `2`。详细退出码含义是：

- `0`：命令成功且没有变更。
- `1`：发生错误。
- `2`：命令成功且存在变更。

审阅已经保存的计划：

```powershell
terraform show -no-color .\release-v1.tfplan
```

计划应创建一个 Bucket 与一个 `release.txt` object，object 内容为 `v1`。

### Task 4：应用同一份 v1 Plan

```powershell
terraform apply -input=false .\release-v1.tfplan
terraform state list
terraform output release_contract
```

应用 saved plan 时不要再次传 `-var`，也不要重新运行普通 apply；变量和动作已经冻结在 plan 制品中。state 应包含：

```text
aws_s3_bucket.release
aws_s3_object.manifest
```

### Task 5：用退出码控制 v2 发布

先证明相同输入已经收敛：

```powershell
terraform plan -input=false -detailed-exitcode -var='release=v1'
$LASTEXITCODE
```

退出码必须是 `0`。然后创建 v2 plan：

```powershell
terraform plan -input=false -detailed-exitcode `
  -out=release-v2.tfplan `
  -var='release=v2'
$LASTEXITCODE

terraform show -no-color .\release-v2.tfplan
terraform apply -input=false .\release-v2.tfplan
```

v2 plan 的退出码必须是 `2`，并且只更新 manifest object，不能重建 Bucket。

### Task 6：核验最终发布并删除 Plan 制品

```powershell
terraform plan -input=false -detailed-exitcode -var='release=v2'
$LASTEXITCODE
terraform output release_contract
aws --endpoint-url=http://localhost:4566 s3 cp `
  s3://tfpro-challenge74-release/release.txt -
```

退出码必须为 `0`，CLI 读取到的对象内容必须是 `v2`。随后删除临时 plan：

```powershell
Remove-Item .\release-v1.tfplan, .\release-v2.tfplan -Force
```

## 清理

```powershell
terraform destroy -auto-approve -var='release=v2'
Remove-Item -Path .\release-*.tfplan -Force -ErrorAction SilentlyContinue
```

确认目录最终只保留 `Readme.md` 和 `challenge-74.tf`，不保留 plan、state、lock 或 `.terraform/`。

## 考纲对应

- 1b / 1c：生成、审阅并应用 saved execution plan。
- 3c：使用非交互输入与详细退出码建立自动化门禁。

官方入口：[`terraform plan`](https://developer.hashicorp.com/terraform/cli/commands/plan)、[`terraform show`](https://developer.hashicorp.com/terraform/cli/commands/show)、[`terraform apply`](https://developer.hashicorp.com/terraform/cli/commands/apply)。
