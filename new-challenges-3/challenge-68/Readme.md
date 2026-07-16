# Challenge 68：CLI Workspace 的 Dev/Prod State 隔离

## 题目目标

同一份 Terraform 配置要分别管理 dev 和 prod 的 S3 release，但两个环境必须拥有独立
local state。你将创建、切换、验证并删除 Terraform CLI workspaces，同时证明相同资源
地址在不同 workspace 中可以对应不同远端对象。

考纲对应：CLI workspace、state 隔离、plan/apply/destroy 工作流与条件保护。

> [!IMPORTANT]
> 本题练习的是 Terraform CLI workspace，不是 HCP Terraform workspace。二者名称相似，
> 但运行方式、权限模型和协作能力不同。

## 开始前检查

在 `new-challenges-3/challenge-68` 中执行：

```powershell
Invoke-RestMethod http://localhost:4566/_localstack/health
terraform init
terraform validate
terraform workspace list
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

预期初始只有 `default`。starter 不允许在 default 中部署；dev 和 prod 都必须先显式创建。

## Task 1：验证 default workspace 的保护

```powershell
terraform workspace show
terraform plan
```

预期当前名称为 `default`，plan 因 resource precondition 失败，并提示先选择 dev 或 prod。
这证明输入保护发生在 plan，而 `init` 和静态 `validate` 本身可以成功。

## Task 2：创建并部署 dev workspace

```powershell
terraform workspace new dev
terraform workspace show
terraform plan '-out=dev.tfplan'
terraform apply dev.tfplan
terraform state list
terraform output workspace_contract
```

预期 workspace 为 `dev`，plan 创建一个 bucket 和一个 object。managed resource 地址为
`aws_s3_bucket.environment` 与 `aws_s3_object.release`，输出中的 bucket 名包含 `dev`，
release 为 `dev-2026.07`。

官网入口：[Manage workspaces](https://developer.hashicorp.com/terraform/cli/workspaces)。

## Task 3：创建独立的 prod workspace

不要销毁 dev。创建 prod 后再次部署同一份配置：

```powershell
terraform workspace new prod
terraform plan '-out=prod.tfplan'
terraform apply prod.tfplan
terraform state list
terraform output workspace_contract
```

预期 prod state 中仍显示相同的两个资源地址，但 bucket 名包含 `prod`，release 为
`prod-2026.07`。相同地址只在各自 workspace 的 state 内唯一。

## Task 4：证明切换不会串改环境

先记录 prod 输出，再切回 dev：

```powershell
terraform output workspace_contract
terraform workspace select dev
terraform output workspace_contract
terraform plan
aws --endpoint-url http://localhost:4566 s3api list-buckets --query "Buckets[?contains(Name, 'tfpro-challenge-68')].Name"
```

预期 dev 的完整 plan 为 `No changes`，输出恢复为 dev 合同；LocalStack 同时存在 dev 与
prod 两个 bucket。切换 workspace 只切换 state，不会自动 destroy 另一个环境。

## Task 5：按 workspace 清理并删除 state 容器

必须分别进入两个 workspace destroy，不能只在当前 workspace 执行一次：

```powershell
terraform workspace select prod
terraform destroy -auto-approve
terraform state list
terraform workspace select dev
terraform destroy -auto-approve
terraform state list
terraform workspace select default
terraform workspace delete prod
terraform workspace delete dev
terraform workspace list
Remove-Item .\dev.tfplan,.\prod.tfplan -ErrorAction SilentlyContinue
```

预期两个环境的 state 都先变为空，随后才能删除 workspace；最终只剩 `default`，本题两个
bucket 都已从 LocalStack 删除。

## Terraform 1.6 边界

- `terraform.workspace` 返回当前 CLI workspace 名称，可用于命名，但不是安全边界。
- CLI workspaces 共用相同配置和 backend；它们不提供 HCP 的 RBAC、远程运行或 policy 功能。
- saved plan 属于生成它的 workspace。切换 workspace 后不要 apply 另一个环境的 plan 文件。

## 最终检查

- default workspace 的 plan 被明确阻止。
- dev 与 prod 使用相同地址、不同 state 和不同 bucket。
- 来回切换后两个环境的 plan 都保持独立。
- 两个 workspace 分别 destroy 后才被删除，最终只剩 default。
