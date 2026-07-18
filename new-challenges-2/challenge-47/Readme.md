# Challenge 47：双 Region Alias 与可审计的 Provider Routing

同一个 LocalStack endpoint 可以模拟多个 AWS Region，但 Terraform 不会因为资源名含有
`dr` 就自动选择另一个 provider。本题从单 Region bucket 起步，逐步添加第二个完整 provider
configuration，并用 resource、data source、state 与 S3 API 四类证据证明路由正确。

## 官方考试目标

- **2b**：Query providers using data sources
- **5b**：Configure providers, including aliasing, versioning, sourcing, and managing upgrades

本题范围来自 [Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)，
只使用官方 AWS 学习清单中的 S3 bucket 与 caller identity。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-47
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
terraform init
terraform apply -auto-approve
terraform output primary_contract
~~~

Starter 只有默认 `aws` provider，创建 `tfpro-c47-primary`。先确认 output 的 account ID
为 LocalStack 账户，且第二个 bucket 尚不存在。

## Task 1：为 DR 建立完整 Alias

在 `challenge-47.tf` 中添加 `provider "aws"`，要求：

- alias 固定为 `dr`；
- Region 为 `us-west-2`；
- 凭证、三项 skip flags、S3 path-style 与 S3/STS endpoints 都和默认配置同样完整；
- endpoint 仍是 `http://localhost:4566`，不能改成真实 AWS。

~~~powershell
terraform fmt
terraform validate
terraform providers
~~~

`terraform providers` 仍只显示一个 AWS provider requirement。Alias 是同一 provider
plugin 的第二份 configuration，不是第二个插件版本。

## Task 2：让 Data Source 显式走 DR

添加 `data.aws_caller_identity.dr` 并绑定 `provider = aws.dr`，再输出两边的 account ID。

~~~powershell
terraform plan
terraform apply -auto-approve
terraform output routing_identities
~~~

LocalStack 两个 Region 通常返回相同 account ID；这不能证明 provider 选错了。输出中还要
保留静态的 primary/DR Region 标签，供后续合同消费。

## Task 3：创建只属于 DR Configuration 的 Bucket

添加 `aws_s3_bucket.dr`：

- 物理名称必须为 `tfpro-c47-dr`；
- 显式绑定 `aws.dr`；
- `force_destroy = true`；
- tags 含 `Challenge = "47"` 与 `RegionRole = "dr"`。

先保存计划再应用同一文件：

~~~powershell
terraform plan '-out=c47-dr.tfplan'
terraform show c47-dr.tfplan
terraform apply c47-dr.tfplan
Remove-Item .\c47-dr.tfplan
~~~

计划只应新增一个 bucket，不应替换 primary。

## Task 4：用一次负向实验识别隐式回落

临时删除 DR bucket 的 `provider = aws.dr`，运行 `terraform plan`。配置仍可能通过验证，
因为默认 provider 存在；这正是危险之处。不要应用该计划。恢复显式绑定后再次 plan，应回到
`No changes`。

如果一个 root module 只声明 aliased providers 而没有默认配置，未绑定资源会收到隐式的
空默认配置；那通常在 plan/apply 阶段才暴露缺少 Region 或认证。写下这两种错误的区别。

## Task 5：发布并核对 Routing Contract

把临时 outputs 整理为 `routing_contract`，每个 Region 至少包含 bucket name、期望 Region
与 caller account ID。随后从 state 和 API 双向核对：

~~~powershell
terraform output routing_contract
terraform state show aws_s3_bucket.primary
terraform state show aws_s3_bucket.dr
aws --endpoint-url=http://localhost:4566 s3api get-bucket-location --bucket tfpro-c47-primary
aws --endpoint-url=http://localhost:4566 s3api get-bucket-location --bucket tfpro-c47-dr
terraform plan
~~~

S3 对 `us-east-1` 的 LocationConstraint 可能显示为 null，而 DR 应反映 `us-west-2`。
最终 plan 必须无变更。

## Task 6：销毁并恢复 Starter

~~~powershell
terraform destroy -auto-approve
aws --endpoint-url=http://localhost:4566 s3api list-buckets --query "Buckets[?starts_with(Name, 'tfpro-c47-')].Name"
Remove-Item -Recurse -Force .\.terraform
Remove-Item -Force .\.terraform.lock.hcl, .\terraform.tfstate* -ErrorAction SilentlyContinue
Get-ChildItem -Force
~~~

API 查询应返回空列表。把 `challenge-47.tf` 恢复到只含 primary 的 starter，确保目录最终
只有两份源文件。

## LocalStack 边界

LocalStack 复用同一账户和 endpoint，不会让 caller identity 显示 Region。因此本题必须用
provider binding、S3 bucket location、state 和显式合同共同证明路由，不能只比较 account ID。
