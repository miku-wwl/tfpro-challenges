# Challenge 21：用 `moved` Block 与 `state mv` 重命名地址

物理 bucket 名不变，但 Terraform resource label 要经历两次重命名。第一次使用声明式
`moved` block，让重构意图留在配置中；第二次使用命令式 `terraform state mv`，立即改写
当前 state。你要证明两条路径都不会调用 S3 删除或重建对象。

## 官方考试目标

- **1e**：安全重构资源地址并管理 state
- **2d**：使用 `for_each` meta-argument，并准确处理带 key 的实例地址
- 辅助使用 **1b / 1c**：先审阅破坏性计划，再应用无基础设施动作的迁移计划

本题按 Terraform `>= 1.6.0, < 2.0.0` 设计，AWS provider 为 `5.80.0`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-21
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
Invoke-RestMethod http://localhost:4566/_localstack/health
```

Starter 用单元素 map 驱动 `for_each`。初始完整实例地址是
`aws_s3_bucket.legacy["primary"]`，物理名称是 `tfpro-c21-address-move`。目录没有 state。

## Task 1：创建并记录初始地址与物理身份

```powershell
terraform init -input=false
terraform fmt -check
terraform validate
terraform plan '-out=legacy.tfplan'
terraform apply legacy.tfplan
terraform state list
terraform state show 'aws_s3_bucket.legacy["primary"]'
terraform output -json bucket_contract
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c21-address-move
Remove-Item -LiteralPath .\legacy.tfplan
```

State 只有带引号 key 的 legacy 实例地址，API 成功。后续所有步骤都必须保持同一个物理
bucket 名。

## Task 2：先观察没有迁移声明的危险重命名

把 resource label 从 `legacy` 改成 `archive`，并同步修改 output 中的引用；不要改
`for_each` key、bucket 名、tags 或其他参数，也暂时不要添加 moved block。

```powershell
terraform fmt
terraform validate
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

退出码应为 `2`，计划会把旧地址视为 destroy、把
`aws_s3_bucket.archive["primary"]` 视为 create。即使两者参数相同，Terraform 仍以地址
识别 state object。不要 apply 这份破坏性计划。

## Task 3：用声明式 `moved` Block 完成第一次迁移

添加一个 moved block：`from` 是旧的 legacy `primary` 实例地址，`to` 是新的 archive
`primary` 实例地址。两端都必须写完整 `for_each` key。

```powershell
terraform fmt
terraform validate
terraform plan -input=false '-out=declarative-move.tfplan'
terraform show declarative-move.tfplan
terraform apply -input=false declarative-move.tfplan
terraform state list
```

Plan 应报告地址 moved，摘要为 **0 to add, 0 to change, 0 to destroy**。Apply 只把 state
地址迁到 `aws_s3_bucket.archive["primary"]`；它不创建第二个 bucket。

## Task 4：用 `state mv` 完成第二次迁移

先删除刚才的一次性 moved block，再把 resource label 与 output 引用从 `archive` 改为
`records`。不做 state 操作时，fresh plan 应再次显示一销毁一创建：

```powershell
terraform fmt
terraform validate
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

确认退出码为 `2` 后，先 dry-run，再执行命令式 state move：

```powershell
terraform state mv -dry-run `
  'aws_s3_bucket.archive["primary"]' `
  'aws_s3_bucket.records["primary"]'
terraform state mv '-backup=state-mv.backup' `
  'aws_s3_bucket.archive["primary"]' `
  'aws_s3_bucket.records["primary"]'
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

Dry-run 与正式命令都只能匹配一个实例。最后 plan 退出码必须为 `0`。与 moved block 不同，
`state mv` 已立即修改当前 state，且迁移意图不会保留给其他独立 state 副本。

## Task 5：从 State 与 API 证明没有重建

```powershell
terraform state list
terraform state show 'aws_s3_bucket.records["primary"]'
terraform output -json bucket_contract
aws --endpoint-url=http://localhost:4566 s3api get-bucket-tagging `
  --bucket tfpro-c21-address-move
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

State 只能有 records 地址；output/API 的 bucket 仍是初始物理名称，tags 中 key 仍为
`primary`。最后退出码为 `0`。

## Task 6：由最终地址销毁并恢复 Starter

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c21-address-move
$LASTEXITCODE
```

State 为空且 API 非零。销毁后将源码恢复为初始 legacy 地址，再删除运行产物：

```powershell
git restore --source=HEAD -- .\challenge-21.tf
Remove-Item -LiteralPath .\.terraform -Recurse -Force
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,`
  .\terraform.tfstate.backup,.\declarative-move.tfplan,`
  .\state-mv.backup -Force -ErrorAction SilentlyContinue
git diff --exit-code -- .\challenge-21.tf
Get-ChildItem -Force | Select-Object -ExpandProperty Name
```

最终目录只保留 README 和使用 legacy label 的 starter `.tf`。

## Terraform 1.6 与 LocalStack 边界

- `for_each` key 是实例地址的一部分；PowerShell 中用单引号包住整个含双引号 key 的地址。
- `moved` block 更适合随代码发布的可重复重构；`state mv` 适合受控、即时的单个 state
  维护，但需要协调并发操作者。
- 两种方式都只移动 state 绑定，不改变 S3 bucket 名；一旦计划出现真实 create/delete，
  就应停止而不是 apply。
- State backup 可能含敏感数据。本题显式命名并在清理时删除它。
