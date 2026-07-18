# Challenge 16：双 Provider 发布接管与可复现执行（Hard）

## 场景

两个由旧脚本创建的 S3 bucket 即将交由 Terraform 接管。一次仓促重构把 Provider、版本约束、
输入契约、资源地址、发布对象和输出同时弄坏了。你需要只修改一个 Terraform 文件，并使用
Terraform CLI 完成诊断、Provider 升级、现有资源导入、saved-plan 审阅、apply 和最终收敛。

本题不是命令跟做题。README 只规定业务目标、限制和可验证结果；不会给出逐步解法。

> 建议限时：50–70 分钟。目标难度：Terraform Professional 90–95 分实验题。

## Starter 结构

压缩包内永久源文件必须始终只有：

```text
Readme.md
challenge-16.tf
```

允许 Terraform 在运行时生成 `.terraform/`、`.terraform.lock.hcl`、state 和 plan 文件。
不得新增 module、第二个 `.tf`、`.tfvars`、grader、Shell、PowerShell 或答案文件。

## 环境准备

LocalStack 地址：`http://localhost:4566`

设置测试凭据：

```powershell
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

在一个干净的 LocalStack 环境中创建两个**已存在但尚未进入 Terraform state** 的 bucket：

```text
aws --endpoint-url=http://localhost:4566 s3api create-bucket --bucket tfpro-c16-dev-artifacts
aws --endpoint-url=http://localhost:4566 s3api create-bucket --bucket tfpro-c16-prod-artifacts
```

这两个 bucket 是必须保留的遗留资源，不允许删除后重新创建。

---

## 总体限制

以下任一行为会导致本题最高只能得到 60 分：

1. 删除遗留 bucket 再让 Terraform 创建；
2. 使用 `-target` 绕开完整依赖图；
3. 删除或注释掉任何一个 release target；
4. 把 `for_each` 改成 `count` 或复制成两组静态资源；
5. 在 HCL 中保留字面量 `access_key`、`secret_key` 或其他真实/测试凭据；
6. 保留未设置 alias 的默认 AWS Provider 配置；
7. 使用无参数 `terraform apply`，而不是应用已审阅的 `release.tfplan`；
8. 使用 `terraform state rm`、手工编辑 state 或删除 state 逃避修复；
9. 新增任何持久化源文件或评分脚本。

---

## Task 1：修复 Provider 版本与初始化（15 分）

最终必须满足：

- Terraform CLI 约束为 `>= 1.6.0, < 2.0.0`；
- AWS Provider 允许范围为 `>= 5.80.0, < 5.81.0`；
- 实际选定版本必须属于 `5.80.x`；
- 必须通过正常升级流程生成或更新 `.terraform.lock.hcl`；
- lockfile 必须同时预填充 `windows_amd64` 与 `linux_amd64` 的 Provider package checksum；
- `terraform fmt -check`、`terraform validate` 均成功。

不要把某个本机下载路径、Provider binary 路径或 schema JSON 当作交付物。

## Task 2：重构双 Provider 所有权（15 分）

Root configuration 最终只能有两个 AWS Provider 配置：

- `aws.primary`
- `aws.audit`

两者必须：

- 使用环境变量认证；
- region 为 `us-east-1`；
- S3 和 STS 都连接 `http://localhost:4566`；
- 支持 LocalStack 所需的验证跳过与 path-style S3；
- 不产生隐式空的默认 Provider 被资源误用。

Provider 所有权：

- bucket 与 bucket versioning 必须使用 `aws.primary`；
- manifest、current pointer 和 audit caller identity 必须使用 `aws.audit`；
- primary caller identity 必须使用 `aws.primary`。

最终配置必须证明两个 Provider 指向同一个 LocalStack account；不得把 account ID 写死。

## Task 3：收紧复杂输入契约（15 分）

`release_targets` 必须继续是驱动所有资源的 `map`，并改为严格类型。每个元素包含：

- `bucket_name`：string
- `environment`：string
- `release`：string
- `retention_days`：number
- `extra_tags`：map(string)

必须使用 variable validation 同时保证：

- key 只能并且必须恰好为 `dev`、`prod`；
- 每个元素的 `environment` 与自身 key 完全一致；
- bucket 名以 `tfpro-c16-` 开头并以 `-artifacts` 结尾；
- release 符合 `2026.MM.DD-<environment>` 形式；
- `retention_days` 位于 7–90 天之间。

最终数据必须描述：

| key | bucket | release | retention_days |
|---|---|---|---:|
| dev | `tfpro-c16-dev-artifacts` | `2026.07.18-dev` | 14 |
| prod | `tfpro-c16-prod-artifacts` | `2026.07.18-prod` | 30 |

## Task 4：无损接管遗留 bucket（20 分）

把两个已存在的 bucket 接管到以下稳定资源地址：

```text
aws_s3_bucket.release["dev"]
aws_s3_bucket.release["prod"]
```

要求：

- 不得删除或重建 bucket；
- 接管后 bucket 必须设置 `force_destroy = true`；
- 两个 bucket 都启用 versioning；
- 每个 bucket 最终至少具有这些 tag：
  - `Name`
  - `Challenge = "16"`
  - `Environment`
  - `Release`
  - `RetentionDays`
  - `ManagedBy = "terraform"`
- `extra_tags` 必须合并进入最终 tags，且不能覆盖上述治理 tag。

评分 agent 会检查资源地址、state lineage、真实 bucket 是否仍存在，以及计划中是否出现 bucket delete/create。

## Task 5：恢复跨 Provider 发布链（15 分）

每个环境都必须创建两个 object：

### Manifest

Key：

```text
manifests/<release>.json
```

JSON 至少包含：

- environment
- release
- bucket
- retention_days
- primary_account_id
- audit_account_id

### Current pointer

Key：

```text
channels/current.json
```

JSON 至少包含：

- environment
- release
- manifest_key

额外要求：

- 两类 object 都必须显式使用 `aws.audit`；
- object 必须使用稳定内容哈希避免永久 drift；
- current pointer 必须依赖对应 manifest，而不是复制一个可能失配的独立 key；
- 不能使用 provisioner、`local-exec` 或 AWS CLI 创建 Terraform 应管理的 object。

## Task 6：受控计划与 apply（10 分）

在完成 import 后生成非交互 saved plan：

```text
release.tfplan
```

在 apply 前必须审阅 human-readable 和 JSON 两种形式。获准计划应满足：

- **6 个 create**：2 个 bucket versioning + 2 个 manifest + 2 个 current pointer；
- **2 个 in-place update**：两个已导入 bucket 的 tags；
- **0 个 delete**；
- **0 个 replace**；
- 不得再次 create 两个 bucket；
- apply 必须使用同一个 `release.tfplan`。

如果 Provider 对空 tag state 的表示导致计划摘要与上述数字存在差异，判分以资源级 action 为准：
两个 bucket 只能是 `update` 或 `no-op`，绝不能是 `create`、`delete` 或 `replace`。

## Task 7：输出与最终收敛（10 分）

Root output `release_inventory` 必须按 `dev`、`prod` 分组，并至少返回：

- bucket
- bucket_arn
- versioning_status
- manifest_key
- manifest_etag
- current_key
- current_etag
- primary_account_id
- audit_account_id

完成 apply 后必须达到：

- state 包含 2 个 caller identity data source、2 个 bucket、2 个 versioning 和 4 个 object；
- LocalStack 中两个 bucket、四个 object、tags 和 versioning 均真实存在；
- output 中的值与 state、API 结果一致；
- fresh full plan 的 `-detailed-exitcode` 为 `0`；
- `.terraform.lock.hcl` 与 `release.tfplan` 保留供评分 agent 检查。

---

## Agent 判分合同

本题不附带 grader。评分 agent 应独立检查 HCL、lockfile、saved plan JSON、Terraform state、
output 和 LocalStack API，不接受只凭 README 勾选或终端截图。

建议评分：

- **60 分**：能 init/validate，但仍使用默认 Provider、弱类型或错误资源地址；
- **75 分**：bucket 已导入且可 apply，但 alias 边界、validation、plan 审阅或 object 内容不完整；
- **85 分**：state 与真实资源基本正确，无 destroy/recreate，fresh plan 为 0；
- **95 分**：所有 Provider、import、复杂 validation、saved-plan action 和 output 条件满足；
- **100 分**：再满足 Windows/Linux 双平台 lockfile checksum，并且 starter 之外没有新增持久源文件。

Agent 应对绕过行为直接扣分，而不是只检查最终对象是否“看起来存在”。

## 清理

评分完成后再执行 destroy。由于 bucket 使用 `force_destroy = true`，Terraform 应能删除其管理的
objects 和 bucket。不要在评分前清理，也不要通过删除 state 代替 destroy。
