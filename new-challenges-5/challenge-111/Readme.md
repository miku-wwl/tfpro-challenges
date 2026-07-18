# Challenge 111：从 Git 安装纯计算模块并发布结果

Starter 只有一个可运行的 LocalStack S3 bucket。你会从固定的公共 HTTPS Git 仓库安装 CIDR 模块，先验证纯计算
模块本身不会创建 resource，再让一个 S3 object 消费模块输出。重点是 Git source 语法、重新初始化、模块缓存与
根模块输出，不是手工计算 CIDR。

## 考纲定位与官方资料

- **1a**：添加模块后重新执行 `terraform init`；
- **2e**：消费模块输出并发布根模块 output；
- **4b**：使用 Git module source；
- **3a**：理解 Git ref 与 Registry module version 的差别。

参考：

- [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
- [Module block syntax（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/syntax)
- [Module sources（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)

Git source 必须使用 `git::https://...git?ref=...`。`version` 参数只适用于 Registry 模块，不能与 Git source 一起使用；
`.terraform.lock.hcl` 也不会锁 Git 模块。

## 开始前

```powershell
Set-Location .\new-challenges-5\challenge-111
terraform version
git --version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

Terraform CLI 必须满足 `>= 1.6.0, < 2.0.0`，练习语义限定在 Terraform 1.6；LocalStack Ultimate S3
必须可用，GitHub 必须可从练习环境访问。Starter 只有
`Readme.md` 和 `challenge-111.tf`，没有 init、lock、state 或 plan 产物。

## Task 1：部署最小 S3 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=starter.tfplan'
terraform show starter.tfplan
terraform apply starter.tfplan
Remove-Item -LiteralPath .\starter.tfplan
terraform output starter_bucket
terraform state list
```

计划必须是 **1 add、0 change、0 destroy**，state 只有 `aws_s3_bucket.starter`。此时配置中还没有 module 或 object。

## Task 2：添加固定 tag 的 Git 模块

在 provider 后、bucket 前加入：

```hcl
module "cidr" {
  source = "git::https://github.com/hashicorp/terraform-cidr-subnets.git?ref=v1.0.0"

  base_cidr_block = "10.111.0.0/16"
  networks = [
    {
      name     = "public"
      new_bits = 8
    },
    {
      name     = "private"
      new_bits = 8
    }
  ]
}
```

不要添加 `version`。模块源发生变化后必须重新初始化：

```powershell
terraform init
terraform fmt
terraform validate
terraform plan -detailed-exitcode
$LASTEXITCODE
'module.cidr.network_cidr_blocks' | terraform console
```

plan 退出码必须为 `0`：纯计算模块没有 resource，所以没有远端动作。Console 应显示 `public` 与 `private`
两个不同的 `/24`。

## Task 3：让 S3 object 消费模块输出

添加：

```hcl
resource "aws_s3_object" "network_contract" {
  bucket       = aws_s3_bucket.starter.id
  key          = "network-contract.json"
  content_type = "application/json"
  content = jsonencode({
    challenge = "111"
    networks  = module.cidr.network_cidr_blocks
  })
}

output "git_contract" {
  value = {
    bucket   = aws_s3_bucket.starter.id
    key      = aws_s3_object.network_contract.key
    networks = module.cidr.network_cidr_blocks
  }
}
```

```powershell
terraform fmt
terraform validate
terraform plan '-out=network.tfplan'
terraform show network.tfplan
terraform apply network.tfplan
Remove-Item -LiteralPath .\network.tfplan
terraform output -json git_contract
```

这次计划必须是 **1 add、0 change、0 destroy**，只创建 `aws_s3_object.network_contract`。

## Task 4：审计 Git 模块缓存

```powershell
$moduleIndex = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$moduleIndex.Modules | Select-Object Key,Source,Version,Dir
Get-ChildItem -Force .\.terraform\modules\cidr
Select-String -Path .\.terraform.lock.hcl -Pattern 'terraform-cidr-subnets','module "cidr"'
```

`cidr` 条目的 Source 必须含完整 Git URL 与 `ref=v1.0.0`；Version 列为空，因为它不是 Registry 模块。
最后一条 lockfile 搜索不应匹配任何内容；模块代码只在 `.terraform/modules/cidr` 缓存。

## Task 5：从 state 与 S3 API 验收输出链

```powershell
$contract = terraform output -json git_contract | ConvertFrom-Json
terraform state list
terraform state show aws_s3_object.network_contract
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket $contract.bucket `
  --key $contract.key `
  --query '{Type:ContentType,Length:ContentLength,ETag:ETag}'
aws --endpoint-url=http://localhost:4566 s3 cp "s3://$($contract.bucket)/$($contract.key)" -
terraform plan -detailed-exitcode
$LASTEXITCODE
```

state 只能有 bucket 与 object；纯计算模块自身没有 state resource。S3 内容中的 networks 必须与 output 一致，
最后 plan 退出码必须为 `0`。

## Task 6：销毁、恢复 Starter 并清理

先保留完整解法销毁 bucket 与 object：

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket --bucket $contract.bucket
$LASTEXITCODE
```

state 必须为空，`head-bucket` 必须失败。然后从 `.tf` 删除 `module.cidr`、`aws_s3_object.network_contract` 与
`git_contract`，保留最初 bucket 和 `starter_bucket` output，再清理：

```powershell
Remove-Item -LiteralPath .\.terraform -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,.\terraform.tfstate.backup `
  -Force -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能有恢复后的 `Readme.md` 与 `challenge-111.tf`。
