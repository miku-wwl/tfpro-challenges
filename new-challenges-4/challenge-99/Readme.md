# Challenge 99：Nested `for_each` 地址与 PowerShell 引号

真实考试中的 resource address 往往同时包含 module instance key 和 resource instance key。
这道题创建 `dev`、`prod` 两个 module instances，每个 module 又用 `for_each` 管理两个
artifacts。你会准确执行 `state show`、一次受控 target 和一次 `-replace`，并理解为什么
这些操作之后必须回到完整 plan。

## 考纲定位

- **1b**：Generate execution plans using `terraform plan` options
- **1c**：Apply configuration changes using `terraform apply` options
- **1e**：Manage resource state and resource addresses
- **4b**：Use a module in configuration

范围依据：[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。

## 起始结构

```text
challenge-99/
├── Readme.md
├── challenge-99.tf
└── modules/release/main.tf
```

根模块以 `dev`、`prod` 为稳定 key 调用两次 module；child 内以 `api.zip`、`worker.zip`
为稳定 key 创建 objects。所有 AWS 操作都走 LocalStack S3/STS。

```powershell
Set-Location .\new-challenges-4\challenge-99
```

## 任务

### Task 1：部署完整地址树

```powershell
terraform init
terraform fmt -check -recursive
terraform validate
terraform apply -auto-approve
terraform state list
```

state 应有 6 个地址：两个 buckets 和四个 objects。完整 leaf 地址形如：

```text
module.release["dev"].aws_s3_object.artifact["api.zip"]
```

记录 dev API object 的 key 与 ETag：

```powershell
terraform state show 'module.release[\"dev\"].aws_s3_object.artifact[\"api.zip\"]'
```

PowerShell 中应把**整个地址**放在单引号内，并用反斜杠转义地址语法中的双引号，避免
Windows native argument parsing 在 Terraform 收到参数前移除它们。

### Task 2：观察不完整地址的失败边界

依次尝试：

```powershell
terraform state show 'module.release.aws_s3_object.artifact'
terraform state show 'module.release[\"dev\"].aws_s3_object.artifact'
```

两条命令都应失败：第一条缺 module instance key，第二条缺 resource instance key。错误不
表示 state 损坏；先从 `terraform state list` 复制精确地址，再执行操作。

### Task 3：只发布一个已审阅的 Nested Leaf

把根模块中 `local.releases.dev.serial` 从 `1` 改为 `2`。完整 plan 应显示 dev 下两个
objects 都需更新：

```powershell
terraform plan
```

现在只为 dev API leaf 生成定向恢复计划：

```powershell
terraform plan `
  '-target=module.release[\"dev\"].aws_s3_object.artifact[\"api.zip\"]' `
  '-out=dev-api.tfplan'
terraform show dev-api.tfplan
terraform apply dev-api.tfplan
```

Saved plan 只能更新一个 object。`-target` 是异常恢复工具，不是日常“分批部署”机制；
这个步骤结束后配置意图仍未完全收敛。

### Task 4：受控替换一个 Prod Leaf

Prod serial 仍为 `1`。为 prod worker 增加一次显式替换意图：

```powershell
terraform plan `
  '-replace=module.release[\"prod\"].aws_s3_object.artifact[\"worker.zip\"]' `
  '-out=prod-worker-replace.tfplan'
terraform show prod-worker-replace.tfplan
terraform apply prod-worker-replace.tfplan
```

计划必须替换精确的 prod/worker leaf，不得替换整个 module、bucket 或 dev API object。
同时应包含 Task 3 尚未收敛的 dev worker 原地更新：`-replace` **只增加替换意图，并不会像
`-target` 那样缩小完整计划范围**。因此应用前必须审阅这两个动作。`-replace` 比先执行
deprecated `terraform taint` 更容易把意图留在 saved plan 中。

### Task 5：回到完整依赖图并收敛配置意图

```powershell
terraform plan '-out=converge.tfplan'
terraform show converge.tfplan
terraform apply converge.tfplan
terraform plan -detailed-exitcode
```

Task 4 的完整计划已经同时补齐 dev worker，因此这里的完整 plan 应为零变更，最终退出码
必须为 `0`。核对两个环境：

```powershell
terraform output release_contracts
aws --endpoint-url=http://localhost:4566 s3 cp `
  s3://tfpro-c99-dev/artifacts/worker.zip -
aws --endpoint-url=http://localhost:4566 s3 cp `
  s3://tfpro-c99-prod/artifacts/worker.zip -
```

dev 内容 serial 为 `2`，prod 为 `1`。

## 最终验收

```powershell
terraform fmt -check -recursive
terraform validate
terraform state list
terraform plan -detailed-exitcode
```

必须仍有 6 个稳定地址；没有 state mv、临时 taint 或未收敛变更。

## 清理

```powershell
terraform destroy -auto-approve
Remove-Item -Force dev-api.tfplan,prod-worker-replace.tfplan,converge.tfplan `
  -ErrorAction SilentlyContinue
```

不要提交 plan、state、lockfile 或 `.terraform`。

## Terraform 1.6 边界

本题只使用 Terraform 1.6 的 module/resource `for_each` 地址、`-target`、`-replace` 和
saved plan。不要使用 1.7+ `removed` block 或 import `for_each`。考试在 Linux 环境中，
resource address 语义相同；本 README 的单引号写法针对当前 PowerShell 练习环境。
