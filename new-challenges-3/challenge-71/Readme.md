# Challenge 71：跨平台 Provider Lock 与只读初始化

这一题练习团队如何让 Terraform 1.6 在 Windows 开发机和 Linux 自动化环境中使用同一份 Provider 选择。你会生成 dependency lock、补齐两个平台的校验和，并比较 `-lockfile=readonly` 与 `-upgrade` 的职责。

本题只使用 LocalStack S3。仓库中的 starter 只包含 `Readme.md` 和 `challenge-71.tf`；`.terraform/`、`.terraform.lock.hcl`、state 都是练习时生成的运行产物。

> 真实项目通常应把 `.terraform.lock.hcl` 提交到版本控制，让变更经过 code review。本练习的交付约束只允许 md/tf，因此练习结束后需要删除它；不要把这个限制误当成生产最佳实践。

## 开始前检查

在 `new-challenges-3/challenge-71` 目录执行：

```powershell
terraform version
docker ps
Invoke-RestMethod http://localhost:4566/_localstack/health
```

确认 Terraform 是 1.6.x。`challenge-71.tf` 已将 Terraform 约束为 `~> 1.6.0`，并将 AWS Provider 精确固定为 `5.80.0`。

## 任务

### Task 1：生成第一份 Provider selection

执行初始化：

```powershell
terraform init
terraform providers
```

检查 `.terraform.lock.hcl`。它必须记录 `registry.terraform.io/hashicorp/aws`，选择版本必须是 `5.80.0`。理解下面两个边界：

- `required_providers` 声明配置允许的版本。
- lock file 记录这次初始化实际选择的版本与包校验和。

此时不要 apply；先完成团队可复现初始化。

### Task 2：锁定 Windows 与 Linux 包

为考试机/开发机常见的两个平台补齐校验和：

```powershell
terraform providers lock `
  -platform=windows_amd64 `
  -platform=linux_amd64
```

再次查看 lock file。`hashes` 应同时覆盖两个平台，而 Provider 版本仍是 `5.80.0`。记录文件哈希，供下一步比较：

```powershell
Get-FileHash .terraform.lock.hcl -Algorithm SHA256
```

### Task 3：模拟协作者的只读初始化

只删除 Provider/module 缓存，保留 lock file：

```powershell
Remove-Item -LiteralPath .terraform -Recurse -Force
terraform init -lockfile=readonly
Get-FileHash .terraform.lock.hcl -Algorithm SHA256
```

初始化必须成功，前后文件哈希必须一致。`readonly` 的含义是按已有 selection 和 checksum 安装；如果需要改 lock，它应该直接失败，而不是静默重写。

### Task 4：观察互斥模式的预期失败

执行下面这条命令：

```powershell
terraform init -upgrade -lockfile=readonly
```

这是本题的**预期失败**：`-upgrade` 要求 Terraform 重新考虑依赖选择，`-lockfile=readonly` 又禁止更新选择，两种意图互相冲突。不要通过删除版本约束来绕过错误。

### Task 5：执行受约束的 upgrade 并部署

使用允许改 lock 的模式重新初始化：

```powershell
terraform init -upgrade
terraform validate
terraform apply -auto-approve
terraform state list
terraform plan
```

由于 HCL 精确约束 AWS Provider `5.80.0`，`-upgrade` 仍必须选择 `5.80.0`，不能越界安装 6.x。最终 state 中应只有：

```text
aws_s3_bucket.artifact
```

最后一次 plan 必须显示 `No changes`。

## 清理

仍在本题目录执行：

```powershell
terraform destroy -auto-approve
Remove-Item -LiteralPath .terraform -Recurse -Force
Remove-Item -LiteralPath .terraform.lock.hcl -Force
Remove-Item -Path terraform.tfstate* -Force -ErrorAction SilentlyContinue
```

不要把 `.terraform/`、lock、state 或 plan 文件留在 challenge 目录中。

## 考纲对应

- 3a：使用版本约束管理 Terraform binary 与 Provider。
- 5a / 5b：理解 Provider plugin、source、version selection 和升级流程。

官方入口：[Dependency lock file](https://developer.hashicorp.com/terraform/language/files/dependency-lock)、[`terraform init`](https://developer.hashicorp.com/terraform/cli/commands/init)、[`terraform providers lock`](https://developer.hashicorp.com/terraform/cli/commands/providers/lock)。
