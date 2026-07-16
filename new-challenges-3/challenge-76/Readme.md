# Challenge 76：用类型化合同组合两个扁平 Module

这个实验从一个**可以运行、但模块接口很弱**的基线开始。`storage` 和
`publisher` 都接收同一个硬编码 bucket name，因此根模块不得不用显式
`depends_on` 保证发布顺序。你要把这条隐藏约定改成 `output -> input` 数据流，
同时保持现有 AWS 对象和 Terraform 地址不变。

## 考纲定位

- **4a** Create a module
- **4b** Use a module in configuration
- **4c** Refactor a module
- 辅助考点：**2e** complex input/output types、**2d** dependency graph

本题只使用 Terraform 1.6 支持的语法和 Professional AWS 重点资源
`aws_s3_bucket`、`aws_s3_object`。AWS 请求全部发送到 LocalStack
`http://localhost:4566`。

## 起始结构

```text
challenge-76/
├── challenge-76.tf
├── modules/
│   ├── publisher/main.tf
│   └── storage/main.tf
└── Readme.md
```

在 `new-challenges-3/challenge-76` 中执行：

```powershell
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
terraform init
terraform fmt -recursive -check
terraform validate
terraform apply -auto-approve
```

Terraform 必须是 1.6.x，LocalStack 的 S3 服务必须可用。

基线应创建两个地址：

- `module.storage.aws_s3_bucket.this`
- `module.publisher.aws_s3_object.this`

记录 bucket ID，后续重构不得替换它：

```powershell
terraform state show module.storage.aws_s3_bucket.this
```

## 任务

### Task 1：确认当前依赖为什么是“人为的”

阅读根模块中的两个 module calls。`module.publisher` 只收到
`local.bucket_name`，并没有引用 `module.storage` 的任何值；如果删除
`depends_on`，Terraform 无法从数据引用推导先后顺序。

执行以下命令查看当前 provider/module tree 和依赖图文本：

```powershell
terraform providers
terraform graph
```

此时不要修改 state，也不要先删除 `depends_on`。

### Task 2：从 storage 发布类型化合同

修改 `modules/storage/main.tf`，新增名为 `bucket` 的 output。它必须是一个
object，且只发布下列稳定接口：

| 属性 | 来源 |
| --- | --- |
| `name` | `aws_s3_bucket.this.bucket` |
| `arn` | `aws_s3_bucket.this.arn` |

不要输出整个 resource object，也不要在 child module 中增加 provider block。

运行 `terraform validate`。由于尚未有消费者使用新 output，plan 应为
`No changes`。

### Task 3：让 publisher 接收同一个合同

修改 `modules/publisher/main.tf`：

1. 用一个名为 `bucket` 的 `object({ name = string, arn = string })` input
   取代 `bucket_name`。
2. 为该 input 添加 validation，要求 ARN 等于
   `arn:aws:s3:::<name>`。
3. `aws_s3_object.this.bucket` 只从 `var.bucket.name` 取得。

先执行 `terraform fmt -recursive` 和 `terraform validate`。此时根 module call
尚未适配新接口，validate 出现“缺少 `bucket` / 不支持 `bucket_name`”属于本步的
预期中间状态；继续完成 Task 4，不要 apply。

### Task 4：在根模块接通 output -> input

修改 `challenge-76.tf` 中的 `module.publisher`：

- 把 `module.storage.bucket` 传给新的 `bucket` input。
- 删除已经重复的 `bucket_name` argument。
- 删除 `depends_on`；值引用现在会自动形成依赖。
- `module.storage` 的物理 bucket name 保持
  `tfpro-challenge76-artifacts`，不得改名。

现在执行：

```powershell
terraform validate
terraform plan
```

验收结果必须是 `No changes`。如果计划替换 bucket 或 object，说明你改变了
资源地址或实际参数；先修正，不能 apply 该计划。

### Task 5：发布最小 release contract

在 `modules/publisher/main.tf` 中给 object 显式设置
`etag = md5(var.content)`，再新增 `release` output，只包含 `bucket`、`key`、
`etag`。本题 content 很小、单段上传且不使用 KMS，因此这个 digest 可让变更计划和
apply 后的 output 都是确定值；不要把该假设泛化到 multipart 或加密对象。随后修改根
`release_location` output，使其直接透传 `module.publisher.release`，不要在根模块
再次拼装相同数据。

```powershell
terraform apply -auto-approve
terraform output
terraform state list
```

地址仍应只有原来的两个 managed resources；模块接口重构本身不应创建新资源。

### Task 6：确认依赖合同能传播一次真实变更

把 `release_version` 的 default 从 `v1` 改为 `v2`，再运行 plan。预期只有
`module.publisher.aws_s3_object.this` 原地更新，其 `content` 与 `etag` 一起变化；
bucket 为 0 change。

```powershell
terraform apply -auto-approve
terraform plan
```

最终 plan 应为 `No changes`，root output 中的 bucket/key/etag 都有值。

## 最终验收

- `storage` 输出一个最小、类型清晰的 bucket contract。
- `publisher` 通过 typed input 消费合同，不硬编码 bucket name。
- 根模块没有 module-level `depends_on`，依赖由值引用自动形成。
- 两个 managed resource 地址和 baseline bucket ID 都未变化。
- child modules 只有 `required_providers`，没有 provider configuration。

## 清理

仍在 `challenge-76` 目录执行：

```powershell
terraform destroy -auto-approve
```

本题参考：[Module composition](https://developer.hashicorp.com/terraform/language/modules/develop/composition)、[Module development](https://developer.hashicorp.com/terraform/language/modules/develop)。
