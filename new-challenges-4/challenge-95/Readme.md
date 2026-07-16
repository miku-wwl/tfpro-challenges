# Challenge 95：Remote S3 Backend 的 `workspace_key_prefix` 隔离

CLI workspaces 只有在 backend 的真实 key layout 也正确时，才能形成可靠的 state 隔离。
本题在 LocalStack S3 backend 中分别部署 dev 与 prod，直接核对两个 state objects 的路径，
并证明切换 workspace 不会串改另一个环境。

## 考纲定位

- **3b**：Configure remote state
- **3d**：Share data across configurations and workspaces
- 辅助使用 **1a–1d**：init、plan、apply 与按 workspace destroy

## State 边界与 Key 规则

```text
challenge-95/
├── Readme.md
├── bootstrap/
│   └── bootstrap.tf
└── workload/
    └── workload.tf
```

- Bootstrap local state 管理 `tfpro-c95-state`。
- Workload backend 的 `key` 是 `workload.tfstate`。
- `workspace_key_prefix` 是 `challenge95/environments`。
- 非 default workspace 的最终 key 为：
  `<prefix>/<workspace>/<key>`。
- Dev/Prod 分别管理 `tfpro-c95-dev-release` 与 `tfpro-c95-prod-release`。

## 开始前

在专用 PowerShell 终端执行：

```powershell
Set-Location .\new-challenges-4\challenge-95
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

这些环境值仅供 LocalStack backend 使用。目录中不应有旧 state、lockfile 或 `.terraform`。

## Task 1：创建独立的 State Bucket

```powershell
Set-Location .\bootstrap
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform output -raw state_bucket
terraform state list
```

输出必须是 `tfpro-c95-state`；不要让 workload 再次管理这个 bucket。

## Task 2：初始化 Partial Backend 并观察 Default 保护

```powershell
Set-Location ..\workload
terraform init `
  '-backend-config=bucket=tfpro-c95-state' `
  '-backend-config=key=workload.tfstate'
terraform workspace show
terraform workspace list
terraform validate
terraform plan
```

初始化和 validation 应成功。当前 workspace 是 `default`，最后的 plan 必须在 resource
precondition 失败，提示只允许 `dev` 或 `prod`。这是预期诊断：default 只作为控制
workspace，不部署业务资源。

## Task 3：创建并部署 Dev Workspace

```powershell
terraform workspace new dev
terraform workspace show
terraform plan '-out=dev.tfplan'
terraform apply dev.tfplan
terraform output workspace_contract
terraform state list
```

预期结果：

- 当前 workspace 为 `dev`。
- 创建 `tfpro-c95-dev-release`。
- State 只有当前 workspace 的 `aws_s3_bucket.release`。

直接核验 backend object：

```powershell
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c95-state `
  --key challenge95/environments/dev/workload.tfstate
```

## Task 4：创建独立的 Prod Workspace

```powershell
terraform workspace new prod
terraform workspace show
terraform plan '-out=prod.tfplan'
terraform apply prod.tfplan
terraform output workspace_contract
terraform state list
```

预期只创建 `tfpro-c95-prod-release`。Dev bucket 不应被删除、改名或导入 prod state。

```powershell
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c95-state `
  --key challenge95/environments/prod/workload.tfstate
```

## Task 5：从 S3 与 CLI 双向证明隔离

列出真实 backend keys：

```powershell
aws --endpoint-url=http://localhost:4566 s3api list-objects-v2 `
  --bucket tfpro-c95-state `
  --prefix challenge95/environments/
```

必须看到：

- `challenge95/environments/dev/workload.tfstate`
- `challenge95/environments/prod/workload.tfstate`

来回切换并检查各自合同：

```powershell
terraform workspace select dev
terraform output workspace_contract
terraform plan -detailed-exitcode

terraform workspace select prod
terraform output workspace_contract
terraform plan -detailed-exitcode
```

两个 detailed-exitcode 都必须为 `0`。Dev output 只能引用 dev bucket，prod output 只能引用
prod bucket。

## Task 6：按 Workspace 安全清理

每个 workspace 都有独立权威 state，必须分别 destroy：

```powershell
# 当前目录：challenge-95/workload
terraform workspace select dev
terraform destroy -auto-approve

terraform workspace select prod
terraform destroy -auto-approve

terraform workspace select default
terraform workspace delete dev
terraform workspace delete prod

Set-Location ..\bootstrap
terraform destroy -auto-approve

Remove-Item Env:AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
Remove-Item Env:AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
Remove-Item Env:AWS_DEFAULT_REGION -ErrorAction SilentlyContinue
Remove-Item -Force ..\workload\dev.tfplan, ..\workload\prod.tfplan -ErrorAction SilentlyContinue
```

最终 `tfpro-c95-state`、dev bucket 和 prod bucket 都应不存在。

## 最终验收清单

- Backend source 不包含 credentials、bucket 或动态插值。
- `workspace_key_prefix` 固定为 `challenge95/environments`。
- Dev/Prod state object 路径与官方 backend 规则一致。
- 两个 workspaces 的 resource state 和 outputs 相互隔离。
- Default workspace 的保护条件始终阻止业务部署。

## Terraform 1.6 边界

本题只使用 Terraform 1.6 CLI workspaces、S3 backend 和 lifecycle precondition。不要把
CLI workspace 与 HCP Terraform workspace 混为一谈；不要使用 HCP/TFE APIs、mock
providers、ephemeral values、write-only arguments或 Terraform 1.7+ 功能。
