# Challenge 108：诊断模块与 Provider 的版本约束冲突

这个实验有一条刻意固定的兼容基线：Registry Security Group 模块 `5.2.0` 搭配 AWS provider `5.80.0`。
你会先部署它，再把模块临时提升到 `6.0.0`，让 `terraform init -upgrade` 暴露真实的约束交集为空；最后只恢复正确的
模块版本，并证明 state 与 LocalStack 对象从未被替换。

## 考纲定位与官方资料

- **1a**：初始化工作目录并理解 `init -upgrade`；
- **3a**：理解 Terraform、provider 与 module 的版本约束；
- **4b / 4c / 5b**：使用和升级 Registry 模块，并理解 child module 的 provider 约束。

参考：

- [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
- [Module block syntax（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/syntax)
- [Module sources（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)
- [`terraform init`（Terraform 1.6）](https://developer.hashicorp.com/terraform/cli/v1.6.x/commands/init)

Registry 模块可以使用独立的 `version` 参数；`.terraform.lock.hcl` 只锁 provider，不会替你锁模块版本。

## 开始前

```powershell
Set-Location .\new-challenges-5\challenge-108
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

使用满足 `>= 1.6.0, < 2.0.0` 的 Terraform CLI；练习语义限定在 Terraform 1.6，并使用 LocalStack Ultimate。
Starter 只有两个源文件，且没有 `.terraform`、lockfile、state 或 plan。

## Task 1：部署已知兼容的基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform show baseline.tfplan
terraform apply baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
$before = terraform output -json security_group_contract | ConvertFrom-Json
terraform state list
```

初始计划必须是 **3 add、0 change、0 destroy**。`$before.name` 为 `tfpro-c108-version-boundary`，三个 managed
resource 位于 `module.baseline` 下。

## Task 2：区分三个版本信息面

```powershell
terraform providers
$moduleIndex = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$moduleIndex.Modules | Select-Object Key,Source,Version,Dir
Select-String -Path .\.terraform.lock.hcl `
  -Pattern 'provider "registry.terraform.io/hashicorp/aws"','version','constraints'
```

验收结果：

- 根配置要求 Terraform `>= 1.6.0, < 2.0.0`；
- `modules.json` 的 `baseline` 记录 Registry source 与模块版本 `5.2.0`；
- lockfile 的 AWS provider selection 是 `5.80.0`，其中没有 Security Group 模块条目。

## Task 3：制造可解释的约束冲突

只把 `module "baseline"` 的版本临时改为：

```hcl
version = "6.0.0"
```

然后重新求解模块与 provider：

```powershell
terraform init -upgrade
$LASTEXITCODE
```

命令必须失败且退出码非零。错误应同时显示根模块的 AWS provider 精确约束 `5.80.0`，以及 Security Group
模块 6.0.0 带来的 `>= 6.29` 约束，因此不存在可选版本。不要运行 plan/apply，也不要为了“让错误消失”把 AWS
provider 升级到 6.x。

## Task 4：恢复支持边界并重新初始化

把模块版本恢复成 `5.2.0`，然后运行：

```powershell
terraform init -upgrade
terraform fmt -check
terraform validate
$moduleIndex = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$moduleIndex.Modules | Select-Object Key,Source,Version,Dir
terraform plan -detailed-exitcode
$LASTEXITCODE
```

`modules.json` 必须重新记录 `5.2.0`；provider 仍是 `5.80.0`；完整 plan 退出码必须为 `0`，即
**0 add、0 change、0 destroy**。

## Task 5：证明失败的初始化没有改动远端对象

```powershell
$after = terraform output -json security_group_contract | ConvertFrom-Json
if ($before.security_group_id -ne $after.security_group_id) { throw 'Security Group ID changed' }
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $after.security_group_id `
  --query 'SecurityGroups[0].{Id:GroupId,Name:GroupName,Vpc:VpcId,Ingress:IpPermissions,Egress:IpPermissionsEgress}'
terraform state show module.baseline.aws_security_group.this[0]
```

API 与 state 中必须仍是同一个 ID、同一个 VPC 和同一个名称；ingress 为 TCP/443，CIDR 为 `10.108.0.0/16`。
失败的 `init` 只影响本地依赖求解，不会自行修改 state 或 AWS API 对象。

## Task 6：销毁并恢复干净 Starter

确认文件已经恢复 `5.2.0` 后再销毁：

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $after.security_group_id
$LASTEXITCODE
Remove-Item -LiteralPath .\.terraform -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,.\terraform.tfstate.backup `
  -Force -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

state 必须为空，API 查询以非零退出码报告目标组不存在。最终目录只能有最初的 `Readme.md` 与
`challenge-108.tf`。
