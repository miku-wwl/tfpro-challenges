# Challenge 96：Provider Filesystem Mirror 与离线式重新初始化

这道题不要求你编写 Provider，也不把 LocalStack 的行为当成考点。你要练的是 Terraform
如何根据 source address、version constraint 和 dependency lock file 选择插件，以及协作者
如何从受控 filesystem mirror 重新初始化同一份配置。S3 bucket 只是用来证明“换安装来源”
没有改变资源合同。

## 考纲定位

- **1a**：Initialize a configuration using `terraform init` and its options
- **3a**：Manage the Terraform binary and providers using version constraints
- **5a**：Understand Terraform's plugin-based architecture
- **5d**：Troubleshoot provider installation errors

范围依据：[Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。

## 起始状态

工作目录：

```powershell
Set-Location .\new-challenges-4\challenge-96
```

Starter 是一份完整、可部署的基线：AWS Provider 固定为 `5.80.0`，通过 LocalStack 的
S3/STS endpoints 创建 `tfpro-c96-provider-mirror`。目录中不应存在 lockfile、state、
`.terraform` 或 mirror 文件。练习中产生的 mirror 和 CLI 配置都放到系统临时目录，不能
提交到 challenge。

先确认 LocalStack 和考试版本的 Terraform 可用：

```powershell
curl.exe http://localhost:4566/_localstack/health
terraform version
```

## 任务

### Task 1：建立可核对的 Provider selection

在 challenge 根目录执行：

```powershell
terraform init
terraform fmt -check
terraform validate
terraform apply -auto-approve
terraform providers
terraform output mirror_contract
```

预期结果：lockfile 选择 `registry.terraform.io/hashicorp/aws 5.80.0`；输出中的 bucket 是
`tfpro-c96-provider-mirror`，account ID 是 `000000000000`。记录下面两个证据：

```powershell
terraform state list
terraform state show aws_s3_bucket.mirror_proof
```

### Task 2：为两个考试常见平台建立 mirror

仍在 challenge 根目录，把已锁定的 Provider 包复制到 challenge 之外：

```powershell
$mirror = Join-Path $env:TEMP 'tfpro-c96-provider-mirror'
Remove-Item -Recurse -Force $mirror -ErrorAction SilentlyContinue
terraform providers mirror '-platform=windows_amd64' '-platform=linux_amd64' $mirror
Get-ChildItem -Recurse $mirror
```

预期结果：mirror 使用 registry hostname、namespace、provider name 的目录层级，并同时
包含 Windows 与 Linux 的 `5.80.0` 包。mirror 是分发缓存，不是 dependency lock file；
两者不能互相替代。

### Task 3：创建只允许该 mirror 的临时 CLI 配置

取得 Terraform 可移植路径格式：

```powershell
$mirrorPath = ((Resolve-Path $mirror).Path -replace '\\','/')
$cliConfig = Join-Path $env:TEMP 'tfpro-c96.tfrc'
$mirrorPath
$cliConfig
```

用编辑器在 `$cliConfig` 指向的位置创建临时文件，并把 `<ABSOLUTE_MIRROR_PATH>` 替换为
上一条命令打印的值：

```hcl
provider_installation {
  filesystem_mirror {
    path    = "<ABSOLUTE_MIRROR_PATH>"
    include = ["registry.terraform.io/hashicorp/aws"]
  }

  direct {
    exclude = ["registry.terraform.io/hashicorp/aws"]
  }
}
```

设置本次 shell 使用这份 CLI 配置：

```powershell
$env:TF_CLI_CONFIG_FILE = $cliConfig
```

这不是 Terraform configuration，也不应放进 challenge。`direct.exclude` 很重要：没有它，
一次成功的 init 不能证明包确实来自 mirror。

### Task 4：用 readonly lockfile 重新安装插件

删除工作目录缓存，但保留 state 和 lockfile：

```powershell
Remove-Item -Recurse -Force .terraform
terraform init -lockfile=readonly
terraform validate
terraform plan -detailed-exitcode
```

预期结果：init 从 filesystem mirror 安装 AWS `5.80.0`；它不改 lockfile。最后一个命令
退出码为 `0`，而不是表示有变更的 `2`。若 mirror 路径、平台或版本错误，init 应失败，
这时应修复供给链输入，不要删除版本约束或改用未锁定版本。

### Task 5：证明插件来源与资源身份是两条边界

```powershell
terraform output mirror_contract
terraform state show aws_s3_bucket.mirror_proof
terraform providers
```

bucket ID 和 account ID 必须与 Task 1 相同。Provider 的安装位置可以变化；state 中的
Provider source address 和受管资源身份不能因此变化。

## 最终验收

```powershell
terraform fmt -check
terraform validate
terraform plan -detailed-exitcode
```

必须满足：配置只选择 AWS `5.80.0`，readonly 初始化成功，计划退出码为 `0`，challenge
目录中没有 mirror 或 CLI 配置文件。

## 清理

```powershell
terraform destroy -auto-approve
Remove-Item Env:TF_CLI_CONFIG_FILE -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $mirror -ErrorAction SilentlyContinue
Remove-Item -Force $cliConfig -ErrorAction SilentlyContinue
```

练习产生的 `.terraform`、lockfile 和 state 也不要提交。

## Terraform 1.6 边界

本题只使用 Terraform 1.6 已有的 `init -lockfile=readonly`、`terraform providers` 和
`terraform providers mirror`。不要引入 Provider 开发 SDK、1.7+ 功能或 HCP Terraform；
HCP Terraform 在当前 Professional 考试中属于 multiple-choice-only 领域。
