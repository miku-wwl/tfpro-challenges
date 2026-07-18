# Challenge 113：用 Git 子目录安装真实的嵌套模块

这个实验直接从 Security Group Git 仓库的 `modules/http-80` 子目录安装模块。该子目录内部又调用同一仓库的根模块，
因此一个 `module.http_80` 会产生 `module.http_80.module.sg...` 的嵌套 state 地址。你会把 source 语法、模块缓存、
嵌套地址与真实 LocalStack EC2 API 规则串成一条可验收链。

## 考纲定位与官方资料

- **1a**：初始化并安装嵌套 Git 模块；
- **4b / 4c**：使用并维护 module source、输入和输出；
- **2e**：发布类型清晰的根模块 output；
- **5b**：检查 root 与 nested modules 的 provider requirements 和默认 provider configuration 继承。

参考：

- [Terraform Professional review guide](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
- [Module block syntax（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/syntax)
- [Module sources（Terraform 1.6）](https://developer.hashicorp.com/terraform/language/v1.6.x/modules/sources)

Git 子目录用双斜杠 `//modules/http-80`，query parameter 必须放在子目录之后。Git source 用 `ref=v5.2.0`，不能
添加 Registry 专用 `version`；lockfile 仍只锁 AWS provider，不锁模块。

## 开始前

```powershell
Set-Location .\new-challenges-5\challenge-113
terraform version
git --version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

使用满足 `>= 1.6.0, < 2.0.0` 的 Terraform CLI；练习语义限定在 Terraform 1.6。启动 LocalStack
Ultimate EC2，并确保 GitHub 可访问。Starter 只有两个源文件，没有 init、lock、state 或 plan 产物。

## Task 1：安装子目录模块并阅读 manifest

```powershell
terraform init
terraform fmt -check
terraform validate
$moduleIndex = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$moduleIndex.Modules | Select-Object Key,Source,Version,Dir
```

manifest 至少要有：

- `http_80`：Source 含完整 Git URL、`//modules/http-80?ref=v5.2.0`，Version 为空；
- `http_80.sg`：代表子目录模块内部的 `module "sg"`，目录指回同一次下载的仓库根模块。

不要手工编辑 manifest；它是 `terraform init` 的安装记录。

## Task 2：保存、审阅并应用嵌套模块计划

```powershell
terraform plan '-out=http.tfplan'
terraform show http.tfplan
terraform apply http.tfplan
Remove-Item -LiteralPath .\http.tfplan
terraform output -json http_contract
```

计划必须是 **4 add、0 change、0 destroy**：一个 Security Group、TCP/80 CIDR ingress、self ingress 与 all egress。
所有 managed resource 都由内层 `module.sg` 创建。

## Task 3：沿模块层级审计 state 地址

```powershell
terraform state list
terraform state show module.http_80.module.sg.aws_security_group.this[0]
terraform state show module.http_80.module.sg.aws_security_group_rule.ingress_rules[0]
terraform state show module.http_80.module.sg.aws_security_group_rule.ingress_with_self[0]
terraform state show module.http_80.module.sg.aws_security_group_rule.egress_rules[0]
```

上述四个地址必须全部存在，且都包含 `module.http_80.module.sg`。`use_name_prefix = false` 保证真实组名精确为
`tfpro-c113-http-80`，而不是带随机后缀的 name prefix。

## Task 4：从 EC2 API 验收固定子模块规则

```powershell
$contract = terraform output -json http_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $contract.security_group_id `
  --query 'SecurityGroups[0].{Id:GroupId,Name:GroupName,Vpc:VpcId,Ingress:IpPermissions,Egress:IpPermissionsEgress,Tags:Tags}'
```

API 返回值必须满足：ID、Name、VPC 与 output 一致；一条 TCP/80 ingress 的 CIDR 是 `10.113.0.0/16`；
另一条 ingress 以当前 Security Group 自身为来源；egress 允许全部协议。以上默认规则来自 `http-80` 子模块，而不是
根配置中重复声明的规则。

## Task 5：区分 source、cache、lock 与 state

```powershell
$moduleIndex = Get-Content -Raw .\.terraform\modules\modules.json | ConvertFrom-Json
$moduleIndex.Modules | Select-Object Key,Source,Version,Dir
Select-String -Path .\.terraform.lock.hcl `
  -Pattern 'terraform-aws-security-group','v5.2.0','module "http_80"'
terraform providers
terraform plan -detailed-exitcode
$LASTEXITCODE
```

lockfile 搜索不得匹配 Git 仓库、tag 或模块 label；`terraform providers` 应显示根配置与嵌套模块都使用
`registry.terraform.io/hashicorp/aws`。最终 plan 退出码必须为 `0`。

## Task 6：销毁嵌套资源并清理 Starter

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $contract.security_group_id
$LASTEXITCODE
Remove-Item -LiteralPath .\.terraform -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,.\terraform.tfstate.backup `
  -Force -ErrorAction SilentlyContinue
Get-ChildItem -Force
```

Destroy 必须删除四个嵌套 managed resource；state 随后为空，API 查询以非零退出码报告组不存在。最终目录只能有
原始 `Readme.md` 与 `challenge-113.tf`。
