# Challenge 110：重命名模块调用而不重建基础设施

模块块的 label 是 state 地址的一部分。这个实验先部署 `module.edge`，然后把业务命名改为更准确的
`module.perimeter`。你会先审阅“只改 label”产生的错误销毁/创建计划，再用模块级 `moved` 声明身份连续性，确保
LocalStack Security Group 的 ID 完全不变。

## 考纲定位与官方资料

- **1e**：推理配置中的 module address 与 state identity；
- **4b / 4d**：使用 Registry 模块，并以 `moved` block 重构 module call label；
- **1b / 1c**：审阅 saved plan，随后应用同一份计划。

参考：

- [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
- [Module block syntax（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/syntax)
- [Module sources（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)

本题使用 Registry 的 `version = "5.2.0"`。模块不会写入 `.terraform.lock.hcl`；lockfile 锁定的是 AWS provider。

## 开始前

```powershell
Set-Location .\new-challenges-5\challenge-110
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

使用满足 `>= 1.6.0, < 2.0.0` 的 Terraform CLI；练习语义限定在 Terraform 1.6，并使用 LocalStack Ultimate
EC2。目录最初只有两个源文件，没有任何运行产物。

## Task 1：部署旧模块地址

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=edge.tfplan'
terraform show edge.tfplan
terraform apply edge.tfplan
Remove-Item -LiteralPath .\edge.tfplan
$before = terraform output -json perimeter_contract | ConvertFrom-Json
terraform state list
```

计划必须是 **3 add、0 change、0 destroy**。三个 managed resource 都在 `module.edge` 下；
`$before.name` 必须为 `tfpro-c110-perimeter`。

## Task 2：只改 label，观察错误身份推断

把：

```hcl
module "edge" {
```

改为：

```hcl
module "perimeter" {
```

同时把 output 的两处 `module.edge` 改成 `module.perimeter`。先不要添加 `moved`。

```powershell
terraform init
terraform fmt
terraform validate
terraform plan '-out=wrong-rename.tfplan'
terraform show wrong-rename.tfplan
```

计划必须显示 `module.edge` 下 **3 destroy**，`module.perimeter` 下 **3 add**。远端参数相同不代表地址相同；
不要 apply 这份计划。

```powershell
Remove-Item -LiteralPath .\wrong-rename.tfplan
```

## Task 3：声明模块调用的迁移关系

在根模块加入：

```hcl
moved {
  from = module.edge
  to   = module.perimeter
}
```

然后生成一份新的 saved plan：

```powershell
terraform fmt
terraform validate
terraform plan '-out=rename.tfplan'
terraform show rename.tfplan
```

每个嵌套 resource 都应显示从旧模块地址移动到新地址；汇总必须是 **0 add、0 change、0 destroy**。

## Task 4：应用 state 迁移并验证地址

```powershell
terraform apply rename.tfplan
Remove-Item -LiteralPath .\rename.tfplan
terraform state list
$after = terraform output -json perimeter_contract | ConvertFrom-Json
if ($before.security_group_id -ne $after.security_group_id) { throw 'Security Group ID changed' }
terraform state show module.perimeter.aws_security_group.this[0]
```

state 中不能再出现 `module.edge`，所有地址必须以 `module.perimeter` 开头。Security Group ID、VPC、Name 均不能改变。

## Task 5：以完整 plan 与 EC2 API 双向验收

```powershell
terraform plan -detailed-exitcode
$LASTEXITCODE
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $after.security_group_id `
  --query 'SecurityGroups[0].{Id:GroupId,Name:GroupName,Vpc:VpcId,Ingress:IpPermissions,Egress:IpPermissionsEgress,Tags:Tags}'
```

plan 退出码必须为 `0`。API 返回 TCP/80 的 `10.110.0.0/16` ingress 和 all egress；ID、Name、VPC
必须与 `perimeter_contract` 一致。

## Task 6：按新地址销毁，再恢复旧 Starter

保留 `module.perimeter + moved` 解法销毁：

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $after.security_group_id
$LASTEXITCODE
```

state 必须为空，API 查询必须以非零退出码报告目标组不存在。最后把模块 label、output 引用恢复为 `edge`，删除
`moved`，并清理运行产物：

```powershell
Remove-Item -LiteralPath .\.terraform -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,.\terraform.tfstate.backup `
  -Force -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能有最初的 `Readme.md` 与 `challenge-110.tf`。
