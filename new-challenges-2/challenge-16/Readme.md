# Challenge 16：修复 Provider 工作流并发布可复现计划

## 场景

你的团队接手了一份可以连接 LocalStack 的 Terraform 配置。当前配置仍使用旧的 AWS
Provider 约束，并把测试凭据直接写在 Provider block 中。团队的新基线要求升级 Provider、
收紧 Terraform CLI 版本范围、改用环境变量认证，并通过一份经过审阅的 saved plan 创建资源。

本题按照 Terraform Authoring and Operations Professional 的实验题风格设计：你需要修改
Starter、选择正确的 CLI 参数，并让最终配置、lockfile、state 与实际资源同时满足验收条件。
README 不提供逐条解法命令。

## 覆盖的考试目标

- **1a**：使用 `terraform init` 及其选项初始化配置
- **1b**：使用 `terraform plan` 及其选项生成执行计划
- **1c**：使用 `terraform apply` 及其选项应用配置
- **3a**：使用版本约束管理 Terraform binary 与 Provider
- **3c**：在自动化场景中使用非交互 Terraform workflow
- **5a**：理解 Provider plugin、配置要求与 lockfile 的职责边界
- **5b**：配置 Provider source、alias、version constraint 与升级
- **5c**：管理 Provider 认证
- **5d**：排查 Provider 初始化与配置错误

## 环境准备

确保 LocalStack 已启动。PowerShell 示例：

```powershell
Set-Location .\challenge-16
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"
Invoke-RestMethod http://localhost:4566/_localstack/health
```

正式考试使用预配置的 Linux 环境，因此完成本题后，建议再在 WSL 或 Linux shell 中独立做一遍。

## Starter 状态

目录初始只有：

- `Readme.md`
- `challenge-16.tf`

Starter 具有以下特征：

- Terraform CLI 只有最低版本，没有上限；
- AWS Provider 被约束在 `5.70.x`；
- Provider 使用默认配置，没有 alias；
- LocalStack 测试凭据被直接写入 HCL；
- 尚未生成 `.terraform/`、`.terraform.lock.hcl`、state 或 plan artifact；
- 尚未创建任何 bucket。

---

## Task 1：建立旧版本基线（15 分）

在**不修改 Starter**的前提下完成初始化和验证，建立升级前基线。

验收条件：

1. 初始化必须是非交互式的；
2. `terraform validate` 成功；
3. 生成 `.terraform.lock.hcl`；
4. lockfile 中选择的 AWS Provider 必须满足 Starter 的 `5.70.x` 约束；
5. 此阶段不得运行 apply，也不得创建 bucket。

> 目的：先让 lockfile 真实锁定旧版本，后续才能考查 Provider 升级，而不是只做一次全新安装。

## Task 2：修复 Provider 与版本管理（35 分）

修改 `challenge-16.tf`，满足以下全部要求：

1. Terraform CLI 版本约束必须为 `>= 1.6.0, < 2.0.0`；
2. AWS Provider source 必须保持为 `hashicorp/aws`；
3. AWS Provider 版本约束必须升级为 `~> 5.80.0`；
4. Provider alias 必须为 `localstack`；
5. `aws_s3_bucket.release_artifact` 必须显式使用 `aws.localstack`；
6. HCL 中不得包含 `access_key` 或 `secret_key`；认证必须来自环境变量；
7. 保留 LocalStack 所需的 endpoint、path-style S3 与 validation skip 设置。

然后重新初始化并解决旧 lockfile 与新约束之间的冲突。

验收条件：

- **不得删除旧 lockfile 来绕过升级问题**；
- 必须使用合适的 `terraform init` 选项更新已锁定的 Provider；
- 更新后的 lockfile 选择 AWS Provider `5.80.x`；
- `terraform fmt -check` 与 `terraform validate` 均成功；
- 配置中不存在明文凭据；
- 此阶段仍不得创建 bucket。

## Task 3：生成并应用唯一获准的 Saved Plan（25 分）

创建一份非交互式执行计划，并保存为：

```text
challenge16.tfplan
```

在 apply 前审阅该 artifact。计划必须只包含一个资源创建动作：

```text
aws_s3_bucket.release_artifact
```

验收条件：

1. saved plan 只创建一个 S3 bucket；
2. 不得包含 replace、delete 或其他资源动作；
3. 必须 apply 已保存的 `challenge16.tfplan`；
4. 不得使用无参数 `terraform apply` 重新计算未经审阅的计划；
5. apply 必须为非交互式。

## Task 4：验证 State、实际资源与收敛（25 分）

apply 完成后，验证 Terraform state 与 LocalStack 中的实际资源。

最终资源必须满足：

- Bucket 名称：`tfpro-c16-release-artifact`
- `force_destroy = true`
- Tags：
  - `Name = tfpro-c16-release-artifact`
  - `Challenge = 16`
  - `Environment = exam`
  - `ManagedBy = terraform`

最终验收条件：

1. state 中只有 `aws_s3_bucket.release_artifact`；
2. `terraform state show` 显示正确 bucket 与 tags；
3. AWS CLI 通过 LocalStack endpoint 可以找到该 bucket；
4. `terraform output -json release_artifact` 返回 bucket ID 与 ARN；
5. fresh plan 使用 `-detailed-exitcode` 时退出码为 `0`；
6. `.terraform.lock.hcl` 必须保留，不得作为清理文件删除。

## 可选清理（不计分）

完成所有验收后，可以销毁资源。销毁后应确认：

- Terraform state 中不再有资源；
- LocalStack 中 bucket 不存在；
- 保留 `challenge-16.tf` 和 `.terraform.lock.hcl`，删除 plan 与本地 state 产物即可。

---

## 自动判定为不合格的情况

出现任意一项，本题视为未达到考试标准：

- 为了升级 Provider 而直接删除 `.terraform.lock.hcl`；
- HCL 中仍存在 `access_key` 或 `secret_key`；
- 使用默认 Provider，而不是 `aws.localstack`；
- apply 时没有使用已审阅的 saved plan；
- 最终 state 与实际 bucket 不一致；
- fresh plan 仍有变更；
- 通过修改 bucket 名称或删除验收 tags 来规避任务。

## 本题不要求的内容

以下内容不属于本题评分范围，不应投入时间：

- 遍历 `.terraform/providers` 中的二进制文件；
- 解析 `terraform providers schema -json`；
- 比较 lockfile 的 SHA256 哈希；
- 在默认 local backend 上演示无实际变化的 `init -reconfigure`；
- 记忆 Provider plugin 的磁盘缓存路径。
