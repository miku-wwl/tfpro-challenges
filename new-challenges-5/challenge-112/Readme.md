# Challenge 112：把 Git tag 收紧为不可变 Commit SHA

Starter 已用 Git tag `v1.0.0` 安装 CIDR 模块，并把结果写入 LocalStack S3。你会只把 `ref` 改成该 tag 对应的完整
commit SHA，先观察“模块源已变化、必须 init”的保护错误，再重新安装模块。由于代码内容与输出相同，最终 plan 必须是
零 resource 动作，state serial 与 S3 object ETag 也不能变化。

## 考纲定位与官方资料

- **1a**：模块 source 改变后重新初始化；
- **3a**：使用可复现的版本约束与 source ref；
- **4b / 4c**：使用并维护 Git 模块版本；
- **1b**：精确审阅零动作计划。

参考：

- [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
- [Module block syntax（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/syntax)
- [Module sources（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)
- [Dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock)

Git 模块用 query parameter `ref` 选择 branch、tag 或 commit；不要添加 Registry 专用的 `version`。lockfile 只锁
AWS provider，**不锁 Git 模块**。

## 开始前

```powershell
Set-Location .\new-challenges-5\challenge-112
terraform version
git --version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

使用满足 `>= 1.6.0, < 2.0.0` 的 Terraform CLI；练习语义限定在 Terraform 1.6。启动 LocalStack
Ultimate S3，并确保 GitHub 可访问。目录最初只有两个源文件。

## Task 1：部署 tag 基线并记录身份

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=tag.tfplan'
terraform show tag.tfplan
terraform apply tag.tfplan
Remove-Item -LiteralPath .\tag.tfplan
$before = terraform output -json git_pin_contract | ConvertFrom-Json
$beforeState = terraform state pull | ConvertFrom-Json
[pscustomobject]@{ Lineage = $beforeState.lineage; Serial = $beforeState.serial; ETag = $before.object_etag }
terraform state list
```

计划必须是 **2 add、0 change、0 destroy**，state 只有 bucket 与 object；模块没有 managed resource。

## Task 2：确认 tag 存在于 manifest，而不在 lockfile

```powershell
$moduleIndex = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$moduleIndex.Modules | Select-Object Key,Source,Version,Dir
Select-String -Path .\.terraform.lock.hcl -Pattern 'terraform-cidr-subnets','v1.0.0'
```

`cidr` 的 Source 必须以 `?ref=v1.0.0` 结尾，Version 列为空；lockfile 搜索不得匹配 tag 或仓库名。

## Task 3：修改 source，并观察重新初始化保护

只把 source 的 ref 改为完整 SHA，其他 HCL 一字不改：

```hcl
source = "git::https://github.com/hashicorp/terraform-cidr-subnets.git?ref=52ca061aaea2e8f58c91ac03ca1fae45e44c28bf"
```

先故意不运行 init：

```powershell
terraform validate
$LASTEXITCODE
```

必须以非零退出码失败，并报告模块 source 已改变或模块尚未安装。这个错误阻止 Terraform 误用 `v1.0.0` 的旧缓存；
不要删除 state，也不要手工修改 `modules.json`。

## Task 4：按 Commit SHA 重新安装并审阅零动作计划

```powershell
terraform init
terraform validate
$moduleIndex = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$moduleIndex.Modules | Select-Object Key,Source,Version,Dir
$afterInitState = terraform state pull | ConvertFrom-Json
if ($beforeState.lineage -ne $afterInitState.lineage -or $beforeState.serial -ne $afterInitState.serial) {
  throw 'State changed during module re-initialization'
}
terraform plan '-out=sha.tfplan'
terraform show sha.tfplan
Remove-Item -LiteralPath .\sha.tfplan
```

manifest 的 Source 必须以完整 SHA 结尾。该 SHA 与 tag 指向同一份模块内容，因此 plan 必须是
**0 add、0 change、0 destroy**；重新 init 也不能改变 state lineage 或 serial。

## Task 5：证明远端契约完全相同

```powershell
$after = terraform output -json git_pin_contract | ConvertFrom-Json
if ($before.bucket -ne $after.bucket -or $before.object_etag -ne $after.object_etag) {
  throw 'Remote contract changed'
}
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket $after.bucket `
  --key $after.key `
  --query '{Type:ContentType,Length:ContentLength,ETag:ETag}'
terraform plan -detailed-exitcode
$LASTEXITCODE
```

bucket、key、network map、ETag 都必须与 `$before` 相同；API ETag 应与 output 一致；最后 plan 退出码必须为 `0`。

## Task 6：销毁、恢复 tag Starter、清理产物

先用 SHA 配置销毁：

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket --bucket $after.bucket
$LASTEXITCODE
```

state 必须为空，bucket 查询必须失败。随后把 source 的 ref 恢复为 `v1.0.0`，再删除运行产物：

```powershell
Remove-Item -LiteralPath .\.terraform -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,.\terraform.tfstate.backup `
  -Force -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能有 `Readme.md` 与恢复 tag 的 `challenge-112.tf`。
