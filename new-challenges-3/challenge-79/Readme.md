# Challenge 79：给 Child Module 建立两个显式 Provider Slots

starter 中的两只 buckets 都隐式继承同一个默认 AWS provider。你要在不改变
resource addresses、不重建 buckets 的前提下，把它重构成清晰的两槽合同：child
声明 `aws.primary` / `aws.audit`，root 分别注入 `aws.east` / `aws.west`。

## 考纲定位

- **5b** Provider aliasing、sourcing、providers in modules
- **4b** Use a module with explicit provider mappings
- **2b** Query a provider with data sources
- 辅助考点：**1e** 保持既有 state 与资源稳定

LocalStack 在同一 `4566` endpoint 模拟两个 Region；本题考的是 Terraform provider
routing，不考 AWS 跨区域架构。Aliased providers 不会自动传入 child module。

## 起始结构与基线

```text
challenge-79/
├── challenge-79.tf
├── modules/audited_pair/main.tf
└── Readme.md
```

在 `new-challenges-3/challenge-79` 中执行：

```powershell
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
terraform init
terraform validate
terraform apply -auto-approve
terraform state list
```

Terraform 必须是 1.6.x，LocalStack 的 S3/STS 服务必须可用。

记录两只 baseline buckets 的 ID：

```powershell
terraform state show module.audited_pair.aws_s3_bucket.primary
terraform state show module.audited_pair.aws_s3_bucket.audit
```

后续任务不能改变这两个 resource addresses 或 IDs。

## 任务

### Task 1：确认隐式继承的边界

```powershell
terraform providers
terraform plan
```

当前 child 只有默认 `aws` requirement，root 也只有默认 configuration。plan 应为
`No changes`。先保存一份运行时 state 快照到 challenge 目录外，不要提交：

```powershell
terraform state pull | Out-File -Encoding utf8 ..\challenge-79-before.json
```

### Task 2：在 root 建立两个完整 aliases

修改 `challenge-79.tf`，把默认 provider configuration 拆成两个内容完整的 blocks：

| Root alias | Region | Endpoint |
| --- | --- | --- |
| `aws.east` | `us-east-1` | `http://localhost:4566` |
| `aws.west` | `us-west-2` | `http://localhost:4566` |

每个 block 都必须独立包含 dummy credentials、S3 path style、三个 `skip_*` 参数和
S3/STS endpoints。暂时保留原默认 block，直到 Task 4 的 module mapping 完成，避免
中间配置失去 provider。

### Task 3：在 child 声明并绑定两个 slots

修改 `modules/audited_pair/main.tf`：

1. 在 `required_providers.aws` 中声明 `configuration_aliases`：
   `aws.primary` 和 `aws.audit`。
2. `aws_s3_bucket.primary` 显式使用 `aws.primary`。
3. `aws_s3_bucket.audit` 显式使用 `aws.audit`。
4. 新增两个 `aws_caller_identity` data sources，并分别绑定相同 slots。

此时 root 尚未传入这两个 slots，`terraform validate` 报缺少 provider
configurations 是预期中间状态；不要 apply，继续 Task 4。

### Task 4：在 module call 中做静态映射

修改根 `module.audited_pair` 的 `providers` map：

| Child slot | Root configuration |
| --- | --- |
| `aws.primary` | `aws.east` |
| `aws.audit` | `aws.west` |

Provider references 必须是静态地址，不能用 conditional、`each.key` 或变量动态
选择。完成 mapping 后，删除不再使用的默认 provider block。

```powershell
terraform fmt -recursive
terraform init -reconfigure
terraform validate
terraform plan
```

计划必须是 0 add、0 change、0 destroy。Region/provider routing 改变不应成为
重建这两只既有 LocalStack buckets 的借口。

### Task 5：输出并核验 routing contract

扩展 child output，使 primary/audit 每一项都包含：

- bucket ID；
- bucket resource 回读的 Region；
- 对应 caller identity 的 account ID。

根 output 继续只透传 child output。然后执行：

```powershell
terraform apply -auto-approve
terraform output
terraform state pull | Select-String -Pattern 'provider.*\.(east|west)'
terraform plan
```

LocalStack caller account 应为 `000000000000`。state 文本应同时引用 east 和 west
provider configurations；最终 plan 为 `No changes`。LocalStack Community 4.14
可能把两只 S3 buckets 的 computed `region` 都回读为 `us-east-1`；本题的可靠路由
证据是 state 中的 `.east` / `.west` provider references，不把该模拟器差异误判成
alias 配置失败。

### Task 6：确认物理资源没有被 provider 重构扰动

再次执行两个 `terraform state show` 命令，并与 baseline 对比 ID。地址仍应为：

```text
module.audited_pair.aws_s3_bucket.primary
module.audited_pair.aws_s3_bucket.audit
```

只改变 provider wiring，不需要 `moved` block，也不允许 destroy/create。

## 最终验收

- root 只有 `aws.east`、`aws.west` 两个 aliased configurations，没有隐式空默认配置。
- child 声明并使用 `aws.primary`、`aws.audit`，不包含 provider blocks。
- module call 静态映射两个 slots。
- 两只 bucket 地址与 ID 保持不变，state 中能看见不同 root aliases。
- caller IDs 为 LocalStack account，最终 plan 为 `No changes`。

## 清理

仍在 `challenge-79` 目录：

```powershell
terraform destroy -auto-approve
Remove-Item -LiteralPath ..\challenge-79-before.json -ErrorAction SilentlyContinue
```

参考：[Providers within modules](https://developer.hashicorp.com/terraform/language/modules/develop/providers)、[Provider configuration](https://developer.hashicorp.com/terraform/language/providers/configuration)。
