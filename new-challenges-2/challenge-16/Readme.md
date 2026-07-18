# Challenge 16：从 `init` 到 Provider Plugin 与 Lockfile

这道题从一份尚未初始化、但语法完整的 S3 配置开始。你会把源码里的版本约束、依赖
lockfile、`.terraform` 中安装的 plugin 和 LocalStack 中的真实 bucket 串成一条证据链。
重点不是记住某个缓存路径，而是分清“配置要求什么”“init 选择并安装了什么”。

## 官方考试目标

- **1a**：使用 `terraform init` 及其选项初始化配置
- **3a**：通过版本约束管理 Terraform binary 与 providers
- **5a**：理解 Terraform 的 plugin-based architecture
- 辅助使用 **1b / 1c**：审阅并应用初始化后的最小计划

本题固定 AWS provider `5.80.0`，Terraform CLI 范围是 `>= 1.6.0, < 2.0.0`。实验只使用
官方学习范围内的 `aws_s3_bucket`。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-16
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
Invoke-RestMethod http://localhost:4566/_localstack/health
```

目录中只有 `Readme.md` 和 `challenge-16.tf`。配置已经声明一个
`tfpro-c16-plugin-probe` bucket，但没有 `.terraform`、lockfile、state 或 plan。Provider
使用字面量测试凭据，S3/STS 都指向 LocalStack；这些凭据只能用于本地模拟环境。

## Task 1：先读 Requirements，再观察未初始化错误

```powershell
terraform version
terraform fmt -check
terraform providers
terraform validate
$LASTEXITCODE
```

`terraform version` 必须满足配置中的版本范围；本套题按 Terraform 1.6 语义设计。
`terraform providers` 应从源码列出 `registry.terraform.io/hashicorp/aws 5.80.0`，但此时还
没有 plugin binary。`terraform validate` 应因 required provider 尚未安装而失败，退出码为
非零；这不是 AWS credentials 或 LocalStack API 错误。

## Task 2：执行可复现、非交互的初始化

```powershell
terraform init -input=false
$LASTEXITCODE
Get-ChildItem -Force
terraform validate
```

预期 init 与 validate 都成功。目录新增：

- `.terraform/`：当前工作目录使用的 provider plugin 安装目录；
- `.terraform.lock.hcl`：记录实际选择的 provider 版本与校验和。

Lockfile 不是 provider binary，也不记录 LocalStack endpoint 或 credentials。

## Task 3：从 Lockfile 与 Plugin Schema 交叉核验

```powershell
Select-String -Path .\.terraform.lock.hcl `
  -Pattern 'registry.terraform.io/hashicorp/aws','version','constraints'
terraform providers
Get-ChildItem .\.terraform\providers -Recurse -File |
  Select-Object FullName,Length

$schema = terraform providers schema -json | ConvertFrom-Json
$awsSchema = $schema.provider_schemas.'registry.terraform.io/hashicorp/aws'
$awsSchema.resource_schemas.PSObject.Properties.Name -contains 'aws_s3_bucket'
```

Lockfile 应显示 AWS `5.80.0`；plugin 路径也应包含该版本。最后一条表达式必须返回
`True`。Schema JSON 来自已安装的 provider plugin，并不是调用 S3 API 得到的结果。

## Task 4：区分 `-upgrade` 与 `-reconfigure`

先记录 lockfile，再运行两种 init 选项：

```powershell
$lockHashBefore = (Get-FileHash .\.terraform.lock.hcl -Algorithm SHA256).Hash
terraform init -upgrade -input=false
$lockHashAfterUpgrade = (Get-FileHash .\.terraform.lock.hcl -Algorithm SHA256).Hash
$lockHashBefore -eq $lockHashAfterUpgrade

terraform init -reconfigure -input=false
terraform validate
```

因为源码精确约束 `5.80.0`，`-upgrade` 不能选择 6.x 或其他 5.x，哈希比较在同一平台上
应为 `True`。`-reconfigure` 重新接受当前 backend 配置；本题使用默认 local backend，
所以它不会迁移 state，也不会创建 AWS 对象。

## Task 5：证明初始化后的 Plugin 能驱动真实资源

```powershell
terraform plan -input=false '-out=init.tfplan'
terraform show init.tfplan
terraform apply -input=false init.tfplan
terraform state list
terraform state show aws_s3_bucket.plugin_probe
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c16-plugin-probe
terraform plan -input=false -detailed-exitcode
$LASTEXITCODE
```

Saved plan 只创建一个 bucket；state 只有 `aws_s3_bucket.plugin_probe`。`head-bucket` 退出码
为 `0`，最后一次完整 plan 退出码也必须为 `0`，表示没有待处理变更。

## Task 6：销毁、验证 API，并恢复两文件 Starter

```powershell
terraform destroy -auto-approve
terraform state list
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c16-plugin-probe
$LASTEXITCODE
```

State list 应为空；`head-bucket` 应返回非零退出码。随后只删除本题已知的运行产物：

```powershell
Remove-Item -LiteralPath .\.terraform -Recurse -Force
Remove-Item -LiteralPath .\.terraform.lock.hcl,.\terraform.tfstate,`
  .\terraform.tfstate.backup,.\init.tfplan -Force -ErrorAction SilentlyContinue
Get-ChildItem -Force | Select-Object -ExpandProperty Name
```

最终只应列出 `Readme.md` 与 `challenge-16.tf`。

## Terraform 1.6 与 LocalStack 边界

- Lockfile 通常应提交以固定 provider 选择；本仓要求每题最终只有两个 starter 源文件，
  因此练习结束后特意删除它。
- `.terraform` 是可重新生成的工作目录，不能用它代替 lockfile。
- `init` 负责 backend/module/provider 初始化，不会创建 `aws_s3_bucket`；资源动作只发生在
  apply。
- LocalStack 使用测试凭据、path-style S3 与本地 endpoint，不代表真实 AWS 认证做法。
