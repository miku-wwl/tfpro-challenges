# Challenge 107：把模块实例从数字位置迁移到业务键

这个实验从一个已经可部署的 Registry Security Group 模块开始。Starter 用 `count` 表示“启用或停用”，因此真实对象被记录在
`module.edge[0]`。你会先亲眼看到直接改成 `for_each` 为什么会产生错误的销毁/重建计划，再用模块级 `moved` 把 state
地址迁移到稳定的业务键 `module.edge["edge"]`。整个迁移不允许改动 LocalStack 中的 Security Group。

## 考纲定位与官方资料

- **2d**：使用 `count`、`for_each` 等 meta-arguments，并推理实例地址；
- **4b / 4d**：使用模块，并以 `moved` block 重构 module instance address；
- **1b / 1c**：保存、审阅并应用执行计划。

只使用 Terraform 1.6 能力。参考：

- [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
- [Module block syntax（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/syntax)
- [Module sources（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)

这里的 `version = "5.2.0"` 只适用于 Terraform Registry 模块。`.terraform.lock.hcl` 锁定 provider，**不锁定模块**；
模块安装记录在 `.terraform/modules/modules.json`。

## 开始前

```powershell
Set-Location .\new-challenges-5\challenge-107
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

Terraform 必须满足 `>= 1.6.0, < 2.0.0`，LocalStack Ultimate 的 EC2、STS 必须可用。Starter 只有
`Readme.md` 和 `challenge-107.tf`，没有 init、lock、state 或 plan 产物。

## Task 1：建立 `count[0]` 基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform show baseline.tfplan
terraform apply baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
terraform state list
$before = terraform output -json edge_contract | ConvertFrom-Json
$before
```

计划必须是 **3 add、0 change、0 destroy**：一个 Security Group、一条 HTTP ingress rule 和一条 egress rule。
state 中的三个 managed resource 地址都以 `module.edge[0]` 开头，例如
`module.edge[0].aws_security_group.this[0]`。`$before.name` 必须是 `tfpro-c107-edge`。

## Task 2：先观察关闭 `count` 的含义

不要改文件，只用变量临时关闭模块：

```powershell
terraform plan '-var=edge_enabled=false' '-out=count-off.tfplan'
terraform show count-off.tfplan
Remove-Item -LiteralPath .\count-off.tfplan
```

计划必须是 **0 add、0 change、3 destroy**。不要 apply；这一步证明 `count` 的数字实例地址同时承载了开关语义。
默认变量仍为 `true`，远端对象没有改变。

## Task 3：直接改为业务键，并审阅错误计划

在 `module "edge"` 中删除 `count`，加入以业务名为键的映射：

```hcl
for_each = var.edge_enabled ? {
  edge = {
    name = "tfpro-c107-edge"
  }
} : {}
```

同时把模块的 `name` 改为 `each.value.name`，把 output 中两处 `module.edge[0]` 改为
`module.edge["edge"]`。此时**不要**添加 `moved`。

```powershell
terraform fmt
terraform validate
terraform plan '-out=wrong-address.tfplan'
terraform show wrong-address.tfplan
```

计划必须显示旧的 `module.edge[0]` 下 **3 destroy**，新的 `module.edge["edge"]` 下 **3 add**。两边参数即使相同，
Terraform 也不会根据远端属性猜测它们是同一个对象。不要 apply 这份计划，然后删除它：

```powershell
Remove-Item -LiteralPath .\wrong-address.tfplan
```

## Task 4：用模块级 `moved` 完成零动作迁移

在根模块中加入：

```hcl
moved {
  from = module.edge[0]
  to   = module.edge["edge"]
}
```

保存并审阅迁移计划：

```powershell
terraform fmt
terraform validate
terraform plan '-out=move.tfplan'
terraform show move.tfplan
terraform apply move.tfplan
Remove-Item -LiteralPath .\move.tfplan
terraform state list
$after = terraform output -json edge_contract | ConvertFrom-Json
if ($before.security_group_id -ne $after.security_group_id) { throw 'Security Group ID changed' }
```

计划应把旧地址标记为 `has moved to`，汇总必须是 **0 add、0 change、0 destroy**。Apply 只提交 state 地址迁移；
新地址全部以 `module.edge["edge"]` 开头，Security Group ID 必须与 `$before` 完全相同。

## Task 5：验收业务键开关与真实 API 对象

```powershell
terraform plan -detailed-exitcode
$LASTEXITCODE
terraform plan '-var=edge_enabled=false'
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $after.security_group_id `
  --query 'SecurityGroups[0].{Id:GroupId,Name:GroupName,Vpc:VpcId,Tags:Tags}'
```

默认 plan 的退出码必须是 `0`。临时关闭时应只计划销毁 `module.edge["edge"]` 下的 3 个对象，不能出现数字地址；
仍然不要 apply。API 返回的 ID、Name、VPC 必须与 `edge_contract` 一致。

## Task 6：销毁、恢复 Starter、清理产物

先保留 `for_each + moved` 解法销毁真实对象：

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $after.security_group_id
$LASTEXITCODE
```

state 必须为空；API 命令应以非零退出码报告目标组不存在。然后把 `challenge-107.tf` 恢复为最初的
`count = var.edge_enabled ? 1 : 0`、`module.edge[0]` output，删除 `for_each` 与 `moved`，再清理：

```powershell
Remove-Item -LiteralPath .\.terraform -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,.\terraform.tfstate.backup `
  -Force -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

最终目录只能看到 `Readme.md` 和 `challenge-107.tf`，并且 `.tf` 已回到可供下一次练习的 Starter 状态。
