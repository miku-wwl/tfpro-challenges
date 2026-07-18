# Challenge 28：把原始集合转换成可发布的 S3 对象清单

发布系统收到一组大小写、空格和启用状态都不统一的 artifact 描述。你需要用 HCL 表达式与
函数完成过滤、规范化、标签合并、清单编码，再用同一份结果创建 S3 objects。整个转换必须
保持声明式，不能在 PowerShell 中预处理数据后复制回 Terraform。

## 官方考试目标

- **2c**：Compute and interpolate data using HCL functions
- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types

本题只使用 `aws_s3_bucket` 与 `aws_s3_object`。配置兼容 Terraform
`>= 1.6.0, < 2.0.0`；不要使用 provider-defined function 或较新版本功能。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-28
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 只有两个源文件，包含：

- S3 指向 LocalStack 的 AWS provider `5.80.0`；
- 三个复杂 artifact 输入，其中两个 enabled、一个 disabled；
- `common_tags` 与空的目标 bucket `tfpro-c28-function-pipeline`；
- 没有 S3 object，也没有规范化 locals 或 manifest。

## Task 1：部署空目的地并熟悉函数结果

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=starter.tfplan'
terraform apply .\starter.tfplan
Remove-Item -LiteralPath .\starter.tfplan
terraform output -json pipeline_starter | ConvertFrom-Json
```

应只创建 1 个 bucket，输出显示 raw item 为 3、enabled item 为 2。用 console 验证将要使用的
函数语义：

```powershell
'lower(trimspace("  TFPRO  "))' | terraform console
'sort(distinct(["docs","config","docs"]))' | terraform console
```

结果应分别为 `"tfpro"` 和排序去重后的 `config/docs` 列表。

## Task 2：构造过滤且规范化的 keyed collection

添加 `published_artifacts` local，并满足以下合同：

- 只保留 `enabled = true` 的输入；
- 用规范化 logical name 作为 map key：`trimspace`、小写、空格替换为连字符；
- object key 去除首尾空格和 `/`，再转为小写；
- 每个值保留 content，并用 `merge` 合并 common tags、输入 tags 和规范化 LogicalName；
- 不得依赖输入 list 的数值索引作为身份。

添加临时 `pipeline_preview` 输出，仅显示规范化 map keys、object keys 与合并标签。

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply -auto-approve
terraform output -json pipeline_preview | ConvertFrom-Json | ConvertTo-Json -Depth 6
```

预览应只有 `read-me` 和 `app-config` 两项；disabled 的 Draft 不得出现。

## Task 3：用同一集合生成确定性 manifest

新增 locals，使用 `keys`、`values`、`sort`、`distinct` 和 `jsonencode` 生成 manifest JSON。
解码后的结构必须包含：

- 排序后的 published logical keys；
- 排序后的最终 object keys；
- 从输入 tags 收集、统一小写并去重排序后的 tiers；
- published item count 和固定来源 `challenge-28`。

用 `artifact_manifest_json` 输出该 JSON 字符串：

```powershell
terraform fmt
terraform validate
terraform apply -auto-approve
terraform output -raw artifact_manifest_json | ConvertFrom-Json | ConvertTo-Json -Depth 5
```

keys 与 tiers 的顺序必须稳定；重复的 Docs tier 只能出现一次。

## Task 4：用 `for_each` 发布两个 artifact objects

创建 `aws_s3_object.artifact`：

- `for_each` 直接使用 `published_artifacts`；
- bucket 引用 `aws_s3_bucket.artifacts.id`；
- key、content 和 tags 来自 `each.value`；
- `.json` 结尾使用 `application/json`，其他对象使用 `text/plain`；
- 资源地址必须使用规范化 logical key，而不是数字索引。

```powershell
terraform fmt
terraform validate
terraform plan '-out=artifacts.tfplan'
terraform show -no-color .\artifacts.tfplan
terraform apply .\artifacts.tfplan
Remove-Item -LiteralPath .\artifacts.tfplan
terraform state list
```

计划应只新增 2 个 artifact objects；state 地址应含 `"read-me"` 和 `"app-config"`。

## Task 5：把 manifest 本身也作为对象发布

添加单独的 `aws_s3_object.manifest`：key 固定为 `manifest.json`，content 直接使用
`artifact_manifest_json` local，content type 为 JSON，tags 合并 common tags 与
`ArtifactType = "manifest"`。再把临时输出整理为最终 `artifact_contract`，至少包含 bucket、
排序后的 published keys、manifest key，以及 artifact logical key 到远端 object ID 的 map。

```powershell
terraform fmt
terraform validate
terraform plan '-out=manifest.tfplan'
terraform apply .\manifest.tfplan
Remove-Item -LiteralPath .\manifest.tfplan
terraform output -json artifact_contract | ConvertFrom-Json | ConvertTo-Json -Depth 6
```

本次计划应只新增 manifest object。

## Task 6：从 API 验证转换结果并清理

```powershell
aws --endpoint-url=http://localhost:4566 s3api list-objects-v2 `
  --bucket tfpro-c28-function-pipeline `
  --query 'sort_by(Contents,&Key)[].Key'
aws --endpoint-url=http://localhost:4566 s3 cp `
  s3://tfpro-c28-function-pipeline/manifest.json -
terraform plan
terraform destroy -auto-approve
terraform state list
```

API 应只列出两个规范化 artifact key 和 `manifest.json`；Draft 不存在；销毁前 plan 为
`No changes`，销毁后 state 为空。删除运行产物：

```powershell
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate, .\terraform.tfstate.backup `
  -ErrorAction SilentlyContinue
Get-ChildItem -File -Filter '*.tfplan' | Remove-Item -Force
Get-ChildItem -Force | Select-Object Name
```

最终只剩 `Readme.md` 和 `challenge-28.tf`。

## LocalStack 提醒

- S3 ListObjects 的原始返回顺序不应作为合同；Terraform 输出与 API 查询都显式排序。
- ETag 是 LocalStack/S3 的实现结果，不适合作为业务 key；`for_each` 使用 logical name。
- PowerShell 只用于查看 JSON，转换逻辑必须留在 HCL 中。
