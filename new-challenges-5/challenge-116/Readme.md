# Challenge 116：发现并修复未固定的 Git `HEAD`

Git source 省略 `ref` 时，Terraform 会下载远程仓库默认分支当时的 `HEAD`。配置今天能工作，不代表下次
`terraform init` 仍会获得相同代码。本题从这个故意不安全的 starter 开始：先记录实际下载的 commit，区分
module cache 与 provider lockfile，再把 source 固定到完整 SHA，并重建 module cache 验证可复现性。

## 官方考试目标

- **1a**：初始化工作目录并使用 `terraform init` 管理依赖
- **3a**：管理 provider 和 module 的版本选择
- **4b / 4c**：使用 module，并安全管理 module 版本
- 辅助使用 **1b / 1c / 1e**：plan、apply、state 与远端对象验收

考纲依据为 [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。
本题严格使用 Terraform 1.6 的
[Git module source](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources#generic-git-repository)与
[dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock)语义。AWS 部分只有
考试资源清单内的 `aws_s3_bucket` 与 `aws_s3_object`。

## Starter 状态

```powershell
Set-Location .\new-challenges-5\challenge-116
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

git --version
aws --endpoint-url=http://localhost:4566 sts get-caller-identity
```

目录只有 `Readme.md` 和 `challenge-116.tf`。Starter 的 Git source 故意没有 `ref`：

```hcl
source = "git::https://github.com/hashicorp/terraform-cidr-subnets.git"
```

它计算 public/private CIDR，并将结果写入 LocalStack S3 bucket
`tfpro-c116-unpinned-git` 的 `network.json`。你的目标不是假定默认分支永远稳定，而是找到并修复风险。

## Task 1：部署未固定的工作基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c116-baseline.tfplan'
terraform show .\c116-baseline.tfplan
terraform apply .\c116-baseline.tfplan
Remove-Item -LiteralPath .\c116-baseline.tfplan

terraform output git_network_contract
terraform state list
terraform plan
```

预期创建一个 bucket 与一个 object；纯计算 module 不会拥有 state resource。output 中应包含两个 `/24`。
最终 plan 必须为 `No changes`。

## Task 2：审计实际下载内容，而不是猜测 `HEAD`

先查看 Terraform 记录的 module 安装目录：

```powershell
$moduleManifest = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$networkModule = $moduleManifest.Modules |
  Where-Object { $_.Key -eq "network" }
$networkModule | Format-List Key,Source,Dir

$resolvedCommit = git -C $networkModule.Dir rev-parse HEAD
$resolvedCommit
git -C $networkModule.Dir status --short
Get-Content -Raw .\.terraform.lock.hcl
```

记录 `rev-parse HEAD` 返回的 40 位 SHA。当前官方仓库 `v1.0.0` 所在的稳定 commit 是：

```text
52ca061aaea2e8f58c91ac03ca1fae45e44c28bf
```

如果默认分支未来前进，你本次下载的 SHA 可能不同；这正是未固定 source 的风险。`modules.json` 记录 source
和安装路径，但不充当版本锁；lockfile 中只应看到 `hashicorp/aws` provider，不会出现 Git module commit。

## Task 3：把 source 固定到完整 commit SHA

把 module source 的 `ref` 改成 Task 2 实测的 `$resolvedCommit`。下面的占位符必须替换为刚才输出的完整
40 位 SHA，不能原样保留：

```hcl
source = "git::https://github.com/hashicorp/terraform-cidr-subnets.git?ref=YOUR_40_CHARACTER_COMMIT_SHA"
```

不改 base CIDR、networks 或任何 AWS resource。然后运行：

```powershell
terraform plan
terraform init -upgrade
terraform validate
terraform plan '-out=c116-pin.tfplan'
terraform show .\c116-pin.tfplan
```

source 变化后的第一个 plan 应要求重新初始化。因为你固定的是本次已经下载并应用的**同一个** commit，
初始化后的计划必须为 `No changes`。即使远程默认分支以后变化，完整 SHA 仍明确表达本题所需代码。删除
保存的空计划：

```powershell
Remove-Item -LiteralPath .\c116-pin.tfplan
```

## Task 4：重建 module cache，验证 source 自己足够明确

先确认 state 和 provider plugin 仍在，再只删除 module cache：

```powershell
terraform state list
Remove-Item -Recurse -Force -LiteralPath .\.terraform\modules
terraform init
terraform validate
```

重新读取安装目录和 commit：

```powershell
$moduleManifest = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$networkModule = $moduleManifest.Modules |
  Where-Object { $_.Key -eq "network" }
$cachedCommit = git -C $networkModule.Dir rev-parse HEAD
$cachedCommit
if ($cachedCommit -ne $resolvedCommit) {
  throw "Module commit changed: expected $resolvedCommit, got $cachedCommit"
}
terraform plan
```

`rev-parse` 必须返回 Task 2 记录的同一 SHA，plan 必须为 `No changes`。删除 cache 是依赖重装实验，
不会删除 Terraform state 或 LocalStack 对象。

## Task 5：把解析后的来源写进可审计合同

重构 `aws_s3_object.contract.content`，仍然使用 `jsonencode`，内容至少包含：

```text
source_kind = "git"
ref         = "Task 2 实测并写入 source 的完整 SHA"
cidrs       = module.network.network_cidr_blocks
```

`ref` 在真实 HCL 中必须是你已经固定的 40 位 literal，而不是上面的说明文字。这是一个显式的运行合同，
不是 Terraform 自动读取 Git metadata。保存并应用计划：

```powershell
terraform fmt
terraform validate
terraform plan '-out=c116-contract.tfplan'
terraform show .\c116-contract.tfplan
terraform apply .\c116-contract.tfplan
Remove-Item -LiteralPath .\c116-contract.tfplan

aws --endpoint-url=http://localhost:4566 s3api get-object `
  --bucket tfpro-c116-unpinned-git `
  --key network.json `
  .\c116-downloaded.json
Get-Content -Raw .\c116-downloaded.json
Remove-Item -LiteralPath .\c116-downloaded.json
terraform plan
```

计划应只更新 object content；读取结果应包含 SHA 与 module 计算的 CIDR。最后 plan 为 `No changes`。

## Task 6：销毁并还原故意未固定的 starter

先保持完整 SHA 配置并销毁：

```powershell
terraform destroy -auto-approve
terraform state list

aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c116-unpinned-git
```

state 应为空，bucket 应不存在。然后把 object content 和 module source 都恢复为 starter，source 再次不带
`ref`。这是为了让下一次练习仍从“发现风险”开始，而不是把答案留在目录里。

```powershell
Remove-Item -Recurse -Force -LiteralPath .\.terraform
Remove-Item -Force -LiteralPath .\.terraform.lock.hcl -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath .\terraform.tfstate.backup -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终只能保留 `Readme.md` 与 starter `challenge-116.tf`。

## 边界提醒

- `.terraform/modules` 是可重建 cache，不是要提交的源代码，也不是 state。
- `git -C <cache> rev-parse` 是本实验对当前 Git cache 的诊断手段；cache 布局不是 Terraform 的稳定公共接口。
- `.terraform.lock.hcl` 保证 provider selection；Terraform 1.6 不为 remote module 写依赖锁。
- 未设置 `ref` 意味着选择远程默认分支的当前 `HEAD`，不是“自动选择稳定版”。
- 完整 SHA 最可复现；可移动 branch/tag 仍依赖远程仓库维护方式。
