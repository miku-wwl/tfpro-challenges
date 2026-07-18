# Challenge 29：用业务 key 保持 `for_each` 地址稳定

服务清单由外部系统按任意顺序提供。如果资源身份绑定 list 下标，只是交换两行就可能造成
无意义替换。你将先验证业务 code 唯一，再把 enabled 服务投影成 keyed map，创建 S3 objects，
最后分别用“重排”和“改 key”证明 Terraform 地址何时稳定、何时有意变化。

## 官方考试目标

- **2c**：Compute and interpolate data using HCL functions
- **2d**：Use meta-arguments in configuration
- **2e**：Configure input variables and outputs, including complex types

本题只使用 `aws_s3_bucket`、`aws_s3_object` 和 Terraform 1.6 HCL 表达式。AWS provider
固定为 `5.80.0`，所有 AWS 操作都指向 LocalStack。

## Starter 状态

```powershell
Set-Location .\new-challenges-2\challenge-29
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

Starter 有一个 `services` list(object) 和 bucket `tfpro-c29-stable-keys`。两个服务 enabled，
一个 disabled；尚无 validation、keyed local 或 S3 objects。目录只能有两个源文件。

## Task 1：部署仅包含 bucket 的基线

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=baseline.tfplan'
terraform apply .\baseline.tfplan
Remove-Item -LiteralPath .\baseline.tfplan
terraform output -json stable_key_starter | ConvertFrom-Json
```

应只创建 bucket。`supplied_codes` 已排序，因此它不会把输入 list 的排列误当作业务变化。

## Task 2：验证 code，并投影成稳定 map

给 `services` 添加 validation，要求：

- 所有 code 去除空格后非空，并只含小写字母、数字或连字符；
- `distinct` 后的 code 数量必须等于输入数量，即业务 key 唯一。

然后添加 `enabled_services` local：只保留 enabled 项，并以每项的 code 为 map key；value
保留 owner 和 payload。添加临时 `enabled_service_keys` 排序输出。

```powershell
terraform fmt
terraform validate
terraform plan '-var=services=[{code=\"api\",owner=\"a\",enabled=true,payload=\"1\"},{code=\"api\",owner=\"b\",enabled=true,payload=\"2\"}]'
```

重复 code 必须触发自定义 validation error。默认值应通过：

```powershell
terraform apply -auto-approve
terraform output -json enabled_service_keys | ConvertFrom-Json
```

输出应只有 `api` 和 `worker`。

## Task 3：按业务 key 创建对象

创建 `aws_s3_object.service`，满足：

- `for_each` 使用 `enabled_services`；
- object key 为 `services/<business-key>.json`；
- content 用 `jsonencode` 编码 code、owner、payload；
- tags 至少含 Challenge、Service 和 Owner；
- 添加 `service_objects` 输出，将 business key 映射到远端 object ID。

```powershell
terraform fmt
terraform validate
terraform plan '-out=services.tfplan'
terraform show -no-color .\services.tfplan
terraform apply .\services.tfplan
Remove-Item -LiteralPath .\services.tfplan
terraform state list
```

应新增 2 个 objects，state 地址应为 `aws_s3_object.service["api"]` 与
`aws_s3_object.service["worker"]`，没有数字下标，也没有 retired 对象。

## Task 4：重排输入并证明零资源变更

在 `services` 默认值中交换 `api` 与 `worker` 两个 object 的顺序，不改任何字段。然后：

```powershell
terraform fmt
terraform validate
terraform plan
terraform state list
```

计划必须显示 `No changes`，两个 state 地址保持不变。若出现 replacement，说明你的
`for_each` key 仍依赖 list index 或排列位置，应修正后再继续。

## Task 5：临时改业务 key，观察有意的地址变化

只把 `api` 的 code 临时改为 `gateway`，其他字段不变，不要应用：

```powershell
terraform plan '-out=rename-key.tfplan'
terraform show -no-color .\rename-key.tfplan
Remove-Item -LiteralPath .\rename-key.tfplan
```

计划应销毁 key 为 `api` 的 object 并创建 key 为 `gateway` 的 object。这不是重排噪音，而是
业务身份真的变化。把 code 恢复为 `api` 后验证：

```powershell
terraform fmt
terraform plan
```

应再次显示 `No changes`。

## Task 6：从地址、输出和 API 联合验收并清理

```powershell
terraform output -json service_objects | ConvertFrom-Json
terraform state show 'aws_s3_object.service["api"]'
aws --endpoint-url=http://localhost:4566 s3api list-objects-v2 `
  --bucket tfpro-c29-stable-keys `
  --query 'sort_by(Contents,&Key)[].Key'
terraform destroy -auto-approve
terraform state list
```

API 应只有 `services/api.json` 和 `services/worker.json`；销毁后 state 为空。清除运行产物：

```powershell
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate, .\terraform.tfstate.backup `
  -ErrorAction SilentlyContinue
Get-ChildItem -File -Filter '*.tfplan' | Remove-Item -Force
Get-ChildItem -Force | Select-Object Name
```

最终目录只能包含 `Readme.md` 和 `challenge-29.tf`。

## LocalStack 提醒

- S3 object ID 与 ETag 不适合作为 `for_each` key；业务 code 才是配置中的稳定身份。
- `for_each` map 的展示顺序不代表创建顺序，本题只要求地址集合稳定。
- 重命名 key 默认表现为旧地址销毁、新地址创建；若业务要求无销毁重命名，应另行使用 moved block。
