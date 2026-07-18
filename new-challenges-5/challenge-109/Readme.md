# Challenge 109：审计并安全重建模块缓存

这个实验把纯计算 Registry CIDR 模块的结果写进 LocalStack S3。你会明确区分 provider lock、module manifest、
module cache 与 Terraform state，然后安全删除**仅本题**的模块缓存，观察 `init -get=false` 的失败路径，最后用普通
`init` 恢复缓存，并证明远端对象和 state 序列都没有变化。

## 考纲定位与官方资料

- **1a**：初始化目录并使用 `-get=false` 理解模块下载行为；
- **3a**：区分 provider selection 与 module version；
- **4b / 4c**：使用 Registry 模块，并维护其安装与版本选择。

参考：

- [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
- [Module block syntax（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/syntax)
- [Module sources（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)
- [Dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock)

`version = "1.0.0"` 是 Registry 模块版本。lockfile 只记录 AWS provider；模块版本与安装目录由配置和
`.terraform/modules/modules.json` 描述。

## 开始前

```powershell
Set-Location .\new-challenges-5\challenge-109
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

使用满足 `>= 1.6.0, < 2.0.0` 的 Terraform CLI；练习语义限定在 Terraform 1.6，并使用 LocalStack Ultimate
S3。Starter 只有两个源文件，尚无任何运行产物。

## Task 1：部署模块输出的远端消费者

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform show baseline.tfplan
terraform apply baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
terraform output -json cache_contract
terraform state list
```

计划必须是 **2 add、0 change、0 destroy**：一个 bucket 和一个 object。CIDR 模块没有 managed resource，
所以 state 只能列出 `aws_s3_bucket.contract` 与 `aws_s3_object.network_contract`。输出网络应为三个不同的 `/24`。

## Task 2：审计 lockfile、manifest 与 state 的边界

```powershell
Select-String -Path .\.terraform.lock.hcl -Pattern '^provider','version','constraints'
$moduleIndex = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$moduleIndex.Modules | Select-Object Key,Source,Version,Dir
$beforeState = terraform state pull | ConvertFrom-Json
$beforeLineage = $beforeState.lineage
$beforeSerial = $beforeState.serial
[pscustomobject]@{ Lineage = $beforeLineage; Serial = $beforeSerial }
```

lockfile 只能有 `registry.terraform.io/hashicorp/aws` provider；`modules.json` 的 `cidr` 条目必须显示
`hashicorp/subnets/cidr` 与 `1.0.0`；state 不保存模块源代码或模块下载包。

## Task 3：只删除已解析确认的模块缓存

下面的守卫必须原样保留：它确认删除目标就是当前 challenge 的 `.terraform/modules`，而不是工作区或其他目录。

```powershell
$terraformDir = (Resolve-Path .\.terraform).Path
$moduleCache = (Resolve-Path .\.terraform\modules).Path
$expectedCache = [IO.Path]::GetFullPath((Join-Path $terraformDir 'modules'))
if ($moduleCache -ne $expectedCache) { throw "Unexpected module cache: $moduleCache" }
Remove-Item -LiteralPath $moduleCache -Recurse -Force
terraform init -get=false
$LASTEXITCODE
```

`init -get=false` 必须以非零退出码失败，并报告 `module.cidr` 未安装或需要运行 `terraform init`。它被明确禁止下载缺失模块，
所以这个失败是预期验收点。不要删除 `.terraform` 整体、lockfile 或 state。

## Task 4：正常恢复缓存，并证明 state 未变化

```powershell
terraform init
terraform validate
$moduleIndex = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$moduleIndex.Modules | Select-Object Key,Source,Version,Dir
$afterState = terraform state pull | ConvertFrom-Json
[pscustomobject]@{ Lineage = $afterState.lineage; Serial = $afterState.serial }
if ($beforeLineage -ne $afterState.lineage -or $beforeSerial -ne $afterState.serial) {
  throw 'State changed while rebuilding the module cache'
}
terraform plan -detailed-exitcode
$LASTEXITCODE
```

普通 `init` 必须重新创建模块目录和 manifest。lineage、serial 必须逐字相同；完整 plan 退出码必须为 `0`，即
**0 add、0 change、0 destroy**。

## Task 5：从 S3 API 验收远端契约

```powershell
$contract = terraform output -json cache_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket $contract.bucket `
  --key $contract.key `
  --query '{Type:ContentType,Length:ContentLength,ETag:ETag}'
aws --endpoint-url=http://localhost:4566 s3 cp "s3://$($contract.bucket)/$($contract.key)" -
```

对象类型必须是 `application/json`，内容必须含 `web`、`app`、`data` 三个键，且与 `cache_contract.networks`
一致。缓存删除与恢复不能触发任何 S3 API 写操作。

## Task 6：销毁并清理所有运行产物

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket --bucket $contract.bucket
$LASTEXITCODE
Remove-Item -LiteralPath .\.terraform -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,.\terraform.tfstate.backup `
  -Force -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

state 必须为空，`head-bucket` 必须以非零退出码报告 bucket 不存在。最终目录只保留 Starter 的
`Readme.md` 与 `challenge-109.tf`。
