# Challenge 30：用 conditional `count` 表达零或一个资源

一个可选功能关闭时不应创建任何 AWS 对象，但输出合同仍必须存在，并把远端字段表示为
`null`；开启时恰好创建一个 bucket 和一个 marker。你将使用 conditional `count`、splat 与
`one()` 建立严格的零或一语义，再证明省略启用变量会按源配置意图安全退役资源。

## 官方考试目标

- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types

本题使用 `aws_s3_bucket` 与 `aws_s3_object`。`one()` 和 conditional `count` 均属于
Terraform 1.6 范围；不要使用 Terraform 1.10 才有的 ephemeral values。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-30
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

目录只有 `Readme.md` 和 `challenge-30.tf`。Starter 包含 AWS provider `5.80.0` 和复杂类型
`feature`，默认 `enabled = false`；没有 managed resource，`starter_contract` 只回显输入。

## Task 1：确认关闭状态是可执行基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=disabled-baseline.tfplan'
terraform apply .\disabled-baseline.tfplan
Remove-Item -LiteralPath .\disabled-baseline.tfplan
terraform output -json starter_contract | ConvertFrom-Json
terraform state list
```

plan 不应创建 AWS 资源，state list 应为空。关闭状态不是错误，也不需要 dummy resource。

## Task 2：添加零或一个 bucket 与 nullable 输出

先给 `feature` 添加 validation：开启时 bucket name 必须以 `tfpro-c30-` 开头，marker key
必须非空；关闭时仍允许同一默认合同通过。

再创建 `aws_s3_bucket.optional`：

- `count` 只能由 `feature.enabled` 决定，false 为 0、true 为 1；
- 名称来自 `feature.bucket_name`；
- tags 至少含 Name 与 Challenge；
- 不要用包含单个元素的 `for_each` map 规避本题。

把 starter 输出替换为始终存在的 `feature_contract` object。其 `bucket_id` 必须对资源 splat
调用 `one()`：零实例时为 null，一个实例时为 ID。

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve
terraform output -json feature_contract | ConvertFrom-Json | ConvertTo-Json -Depth 4
terraform state list
```

默认关闭时没有资源地址，输出 object 存在，`bucket_id` 为 JSON `null`。

## Task 3：让 marker 与 bucket 使用相同基数

添加 `aws_s3_object.marker`，使用与 bucket 相同的 conditional count：

- 通过相同 `count.index` 引用对应 bucket；
- key 来自 `feature.marker_key`；
- content 明确写出 `challenge-30 enabled`；
- tags 含 Challenge；
- 在 `feature_contract` 中增加用 `one()` 得到的 nullable `marker_etag`。

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve
terraform output -json feature_contract | ConvertFrom-Json | ConvertTo-Json -Depth 4
```

关闭状态仍应为 `No changes`，两个远端字段均为 null。不能直接引用 `[0]`，否则零实例时会
产生 invalid index。

## Task 4：保存并应用开启状态计划

不改默认值，使用一次显式复杂变量开启功能：

```powershell
terraform plan '-var=feature={enabled=true,bucket_name=\"tfpro-c30-optional\",marker_key=\"enabled.txt\"}' '-out=enabled.tfplan'
terraform show -no-color .\enabled.tfplan
terraform apply .\enabled.tfplan
Remove-Item -LiteralPath .\enabled.tfplan
terraform output -json feature_contract | ConvertFrom-Json | ConvertTo-Json -Depth 4
terraform state list
```

计划应创建恰好 1 个 bucket 和 1 个 marker。state 地址应以 `[0]` 结尾，两个输出字段均
非 null。用 API 核对：

```powershell
aws --endpoint-url=http://localhost:4566 s3api head-object `
  --bucket tfpro-c30-optional `
  --key enabled.txt
```

## Task 5：省略变量并按默认关闭意图退役

上一步应用的是保存计划中的启用值，并未把该值写回源配置。现在不传 `-var`：

```powershell
terraform plan '-out=disabled.tfplan'
terraform show -no-color .\disabled.tfplan
terraform apply .\disabled.tfplan
Remove-Item -LiteralPath .\disabled.tfplan
terraform output -json feature_contract | ConvertFrom-Json | ConvertTo-Json -Depth 4
terraform state list
```

计划应销毁 marker 和 bucket；应用后 state 为空，输出合同仍存在且远端字段重新为 null。
这也证明 saved plan 保存了当时的变量值，但不会修改 `.tf` 中的默认配置意图。

## Task 6：验证幂等关闭状态并清理

```powershell
terraform plan
aws --endpoint-url=http://localhost:4566 s3api head-bucket `
  --bucket tfpro-c30-optional
```

plan 应显示 `No changes`；API 应报告 bucket 不存在。因为 Task 5 已按配置销毁全部对象，
不要删除 state 来伪造清理。最后移除运行产物：

```powershell
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate, .\terraform.tfstate.backup `
  -ErrorAction SilentlyContinue
Get-ChildItem -File -Filter '*.tfplan' | Remove-Item -Force
Get-ChildItem -Force | Select-Object Name
```

最终只能看到 `Readme.md` 和 `challenge-30.tf`。

## LocalStack 提醒

- LocalStack S3 只承载远端对象；零或一实例、地址 `[0]` 和 `one()` 都是 Terraform 语义。
- 对空 tuple 调用 `one()` 返回 null；若集合超过一个元素则报错，这正好表达本题基数合同。
- CLI `-var` 值属于该次 plan；应用 saved plan 不会把它写回源文件。
