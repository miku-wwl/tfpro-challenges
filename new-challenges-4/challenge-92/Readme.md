# Challenge 92：三层 Module 的 Provider Pass-Through

Provider configuration 不会像普通变量一样自动穿过任意深度的模块树。Starter 使用一个
默认 provider，因此 root → catalog → release 的隐式继承暂时可以工作。你会把 leaf 改成
要求显式 slot，沿调用链逐层暴露并映射两个 provider aliases，最后证明 provider 重构没有
替换两个真实 bucket。

## 考纲定位

- **4b**：Use a module in configuration
- **5b**：Configure providers, including aliasing and providers in modules
- **5d**：Troubleshoot provider errors
- 辅助使用 **1e**：核对重构前后的 state 与物理资源身份

## 起始结构

```text
challenge-92/
├── Readme.md
├── challenge-92.tf
└── modules/
    ├── catalog/
    │   └── main.tf
    └── release/
        └── main.tf
```

Starter 的两个 leaf calls 都隐式继承 root default provider。Task 1 可完整部署；后续两个
validation failure 是刻意安排的诊断检查点，不要跳过。

## 开始前

```powershell
Set-Location .\new-challenges-4\challenge-92
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
```

使用 Terraform 1.6.x，并确认目录中没有旧 state 或 `.terraform`。

## Task 1：部署三层隐式继承基线

工作目录：`new-challenges-4/challenge-92`

```powershell
terraform init
terraform fmt -check -recursive
terraform validate
terraform apply -auto-approve
$before = terraform output -json release_buckets | ConvertFrom-Json
$before
terraform state list
```

预期创建：

- `module.catalog.module.primary.aws_s3_bucket.this` → `tfpro-c92-primary`
- `module.catalog.module.audit.aws_s3_bucket.this` → `tfpro-c92-audit`

保留 `$before`，后面用它证明物理 ID 未改变。

## Task 2：让 Leaf 明确要求 `aws.deployment`

编辑 `modules/release/main.tf`：

1. 添加 Terraform `~> 1.6.0` 和 AWS `5.80.0` requirement。
2. 在 AWS requirement 中声明 `configuration_aliases = [aws.deployment]`。
3. 给 `aws_s3_bucket.this` 添加 `provider = aws.deployment`。

暂时不要修改 catalog 或 root。运行：

```powershell
terraform init
terraform validate
```

`terraform init` 在刷新 module tree 时就必须失败，指出两次 leaf module call 缺少必需的
`aws.deployment` 配置；单独运行 `terraform validate` 会报告同一根因。这个错误说明 leaf
已经建立了合同，而它的直接 caller 尚未履行合同。Provider plugin 已在 Task 1 安装，
所以不要把这里误判为下载故障。

## Task 3：在 Middle Module 建立两个 Slots

编辑 `modules/catalog/main.tf`：

1. 声明 Terraform `~> 1.6.0` 与 AWS `5.80.0`。
2. 声明 `configuration_aliases = [aws.primary, aws.audit]`。
3. 在 `module.primary` 中映射 `aws.deployment = aws.primary`。
4. 在 `module.audit` 中映射 `aws.deployment = aws.audit`。

```powershell
terraform init
terraform validate
```

此时 leaf 缺 slot 的错误应消失，但 `init`/`validate` 仍应失败：root 的
`module.catalog` 尚未提供 middle module 要求的 `aws.primary` 与 `aws.audit`。不要在
middle 或 leaf 中添加 `provider "aws"` 来绕过边界。

## Task 4：由 Root 配置并传入两个 Aliases

编辑 `challenge-92.tf`：

1. 用两个完整 provider blocks 取代原 default provider。
2. 第一个 alias 为 `primary`、Region 为 `us-east-1`。
3. 第二个 alias 为 `audit`、Region 为 `us-west-2`。
4. 两者都保留 `test/test`、S3 path style、三项 skip flags 和 S3 LocalStack endpoint。
5. 在 `module.catalog` 中映射：

```hcl
providers = {
  aws.primary = aws.primary
  aws.audit   = aws.audit
}
```

然后执行：

```powershell
terraform init
terraform fmt -recursive
terraform validate
terraform plan '-out=provider-refactor.tfplan'
terraform show provider-refactor.tfplan
```

预期 plan 为零资源动作。Provider 地址重构不应删除或重建 bucket。应用已审阅的 plan：

```powershell
terraform apply provider-refactor.tfplan
$after = terraform output -json release_buckets | ConvertFrom-Json
$after
$before.primary -eq $after.primary
$before.audit -eq $after.audit
```

最后两行必须都是 `True`。

## Task 5：核验每一层的 Routing Contract

```powershell
terraform providers
terraform state show module.catalog.module.primary.aws_s3_bucket.this
terraform state show module.catalog.module.audit.aws_s3_bucket.this
$state = terraform state pull | ConvertFrom-Json
$state.resources | Select-Object module, type, name, provider
terraform plan -detailed-exitcode
```

必须满足：

- requirements graph 显示 root → catalog → release 三层。
- Root 是唯一拥有 provider configurations 的模块。
- Catalog 只声明两个 slots，release 只声明一个 `deployment` slot。
- State 中能看到 root alias 地址；最终 plan 退出码为 `0`。

## 清理

```powershell
terraform destroy -auto-approve
Remove-Item -Force .\provider-refactor.tfplan -ErrorAction SilentlyContinue
```

确认两个 bucket 均不存在。不要提交 state、plan、lockfile 或 `.terraform`。

## Terraform 1.6 边界

本题使用静态 provider references 与 `configuration_aliases`。Provider references 不能由
字符串、变量或 `for_each` 动态构造。不要使用 mock providers，也不要把 provider block
放回 reusable child module。
