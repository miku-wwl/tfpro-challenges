# Challenge 100：用 `terraform init -from-module` 建立可复现工作目录

`terraform init` 不只会安装 Provider 和 child modules；它还可以把一个 module source 复制
到全新的工作目录，再完成初始化。本题把 challenge 中的 `seed/` 当作受控模板，在系统
临时目录创建真正的工作副本。所有 state、lockfile 和缓存都留在副本中，seed 始终保持
starter 状态。

## 考纲定位

- **1a**：Initialize a configuration using `terraform init` and its options
- **3a**：Manage Terraform, providers, and modules using version constraints
- **4b**：Use a module in configuration

范围依据：[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。

## 起始结构与安全边界

```text
challenge-100/
├── Readme.md
└── seed/
    ├── main.tf
    └── modules/bucket/main.tf
```

`seed` 是完整 root module：它配置 LocalStack，并调用本地 child module 创建
`tfpro-c100-from-module`。**不要在 seed 目录执行 apply**。本题的 Terraform 工作目录
必须是一个全新的系统临时目录。

```powershell
Set-Location .\new-challenges-4\challenge-100
$seed = (Resolve-Path .\seed).Path
$work = Join-Path $env:TEMP 'tfpro-c100-workspace'
$noGetWork = Join-Path $env:TEMP 'tfpro-c100-no-get'
```

若两个目标目录已经存在，先确认它们确实是本题以前产生的临时目录，再删除；不要对未知
路径执行递归删除。

## 任务

### Task 1：从帮助信息确认选项边界

```powershell
terraform init -help
Get-ChildItem -Recurse .\seed
```

确认当前 Terraform 1.6 提供 `-from-module=SOURCE` 和 `-get=false`。Seed 中只有 `.tf`
文件，没有 state、lockfile 或 `.terraform`。

### Task 2：在空目录完成复制与初始化

创建一个确定为空的新目录：

```powershell
if (Test-Path $work) { throw "$work already exists; inspect it before cleanup" }
New-Item -ItemType Directory -Path $work | Out-Null
Set-Location $work
terraform init "-from-module=$seed"
```

预期结果：Terraform 先复制 seed 内容，再安装 child module 和 AWS Provider `5.80.0`。
核对副本：

```powershell
Get-ChildItem -Recurse -Force
terraform providers
terraform fmt -check -recursive
terraform validate
```

工作副本应有 `main.tf`、`modules/bucket/main.tf`、lockfile 和 `.terraform`；原 seed 仍只有
两份 `.tf`。

### Task 3：证明 `-from-module` 只接受空目录

仍在已初始化的 `$work` 中再次执行：

```powershell
terraform init "-from-module=$seed"
```

预期结果：命令拒绝把 source 再复制到非空目录。不要用覆盖或手工拼接绕过保护；普通的
重新初始化只需：

```powershell
terraform init -lockfile=readonly
```

它应成功且不改变 dependency lock file。

### Task 4：观察 `-get=false` 对 Child Module 安装的影响

回到 challenge 根目录的父级上下文，创建第二个空目录：

```powershell
Set-Location (Split-Path $seed -Parent)
if (Test-Path $noGetWork) { throw "$noGetWork already exists; inspect it before cleanup" }
New-Item -ItemType Directory -Path $noGetWork | Out-Null
Set-Location $noGetWork
terraform init "-from-module=$seed" -get=false
terraform validate
```

配置会被复制，但由于禁止安装 child modules，init 或随后的 validate 应明确报告 module
未安装。现在恢复标准初始化：

```powershell
terraform init
terraform validate
```

预期结果：child module 被安装，validation 通过。`-get=false` 不是“更快的正常 init”；
它只适用于调用者已经有意管理 module 安装的特殊流程。

### Task 5：只在工作副本部署并验证隔离

使用 `$work` 作为正式副本：

```powershell
Set-Location $work
terraform plan '-out=seed.tfplan'
terraform show seed.tfplan
terraform apply seed.tfplan
terraform output seed_contract
terraform plan -detailed-exitcode
```

输出 name 必须为 `tfpro-c100-from-module`，最终 plan 退出码为 `0`。再从 challenge 根
检查 seed 没有运行产物：

```powershell
Get-ChildItem -Recurse -Force $seed
```

## 最终验收

- `$work` 是独立 Terraform working directory，并成功管理一个 LocalStack bucket。
- `$noGetWork` 在恢复普通 init 后可 validate。
- 原 `seed/` 中只有两份 `.tf`，没有 state、lockfile 或 `.terraform`。
- 工作副本的 Provider selection 是 AWS `5.80.0`。

## 清理

先销毁唯一拥有基础设施的工作副本：

```powershell
Set-Location $work
terraform destroy -auto-approve
```

确认 `$work` 与 `$noGetWork` 都以系统临时目录为父目录后，才删除它们：

```powershell
$tempRoot = (Resolve-Path $env:TEMP).Path
if ((Split-Path $work -Parent) -ne $tempRoot) { throw 'unsafe work path' }
if ((Split-Path $noGetWork -Parent) -ne $tempRoot) { throw 'unsafe noGet path' }
Remove-Item -Recurse -Force -LiteralPath $work
Remove-Item -Recurse -Force -LiteralPath $noGetWork
```

## Terraform 1.6 边界

本题只使用 Terraform 1.6 的 `init -from-module`、`-get=false`、`-lockfile=readonly` 和
本地 module source。不要加入 1.7+ 功能、脚本、测试文件或远程 module registry；考点
是 working-directory 初始化和 module/provider selection，不是发布 module。
