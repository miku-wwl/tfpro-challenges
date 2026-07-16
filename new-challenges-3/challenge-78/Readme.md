# Challenge 78：移除 Legacy Child Provider，解锁 Module `for_each`

这个 starter **故意不能完成 plan**：根模块对 `module.release` 使用
`for_each`，但 child module 自己包含 `provider "aws"` configuration。Terraform
会把它视为 legacy module，并拒绝 module-level `for_each`。你的任务是根据错误做
最小现代化改造，而不是删除 `for_each`。

## 考纲定位

- **5a** Understand Terraform's plugin-based architecture
- **5b** Configure providers and providers in modules
- **5d** Troubleshoot provider errors
- 辅助考点：**4b** use modules、**2d** module meta-arguments

题目的预期失败发生在 Terraform 配置层，不会向真实 AWS 发请求。修复后，AWS
provider 只能访问 `http://localhost:4566`。

## 起始结构

```text
challenge-78/
├── challenge-78.tf
├── modules/release/main.tf
└── Readme.md
```

## 任务

### Task 1：复现并准确归因 legacy module 错误

在 `new-challenges-3/challenge-78` 中执行：

```powershell
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
terraform init
terraform validate
terraform plan
```

Terraform 必须是 1.6.x。即使 LocalStack 健康，本步仍应因 legacy module 在配置层
失败；这正是要诊断的边界。

预期看到类似“module is incompatible with count, for_each, and depends_on”的错误。
错误对象是 child module 内的 provider configuration，不是 `local.releases` 的
map，也不是两个 bucket names。保留 `for_each`，继续修复 provider ownership。

### Task 2：把 provider configuration 移到 root

同时修改两个文件：

1. 从 `modules/release/main.tf` 删除完整的 `provider "aws"` block。
2. 保留 child module 的 `required_providers`，它只声明 source requirement。
3. 在根 `challenge-78.tf` 添加默认 AWS provider configuration，原 block 中的
   Region、LocalStack endpoints、dummy credentials 和安全 `skip_*` 参数原样迁移。

Provider requirement 告诉 Terraform“需要安装哪个 plugin”；provider
configuration 告诉 plugin“如何连接服务”。可复用 child module 只负责前者。

```powershell
terraform fmt -recursive
terraform init -reconfigure
terraform validate
```

此时 legacy incompatibility 必须消失。

### Task 3：在 module call 中显式传递默认 slot

修改根 `module.release`，增加静态 provider mapping，把 child 的默认 `aws` slot
映射到根的默认 `aws` configuration。

这个简单场景允许隐式继承，但本题要求显式写出映射，以便用
`terraform providers` 审计 provider ownership。Provider mapping 不能根据
`each.key` 动态选择。

### Task 4：部署两个 module instances

```powershell
terraform providers
terraform plan
terraform apply -auto-approve
terraform state list
terraform output release_buckets
```

state 必须包含：

```text
module.release["blue"].aws_s3_bucket.this
module.release["green"].aws_s3_bucket.this
```

PowerShell 查看单个实例时，把完整地址放在单引号中：

```powershell
terraform state show 'module.release["blue"].aws_s3_bucket.this'
```

### Task 5：验证可复用 module 的 provider 边界

执行以下检查：

```powershell
Select-String -Path .\modules\release\*.tf -Pattern '^provider\s+"'
terraform providers
terraform plan
```

第一条命令不应匹配任何 child provider block；provider tree 应显示 child 需要
`registry.terraform.io/hashicorp/aws`，配置由 root 提供；最终 plan 应为
`No changes`。

## 最终验收

- 根 module 拥有唯一 AWS provider configuration。
- child module 只声明 provider requirement，没有 provider block。
- `module.release` 保留 `for_each` 并显式接收 root provider。
- blue/green 两只 buckets 存在，state addresses 使用稳定 string keys。
- `terraform validate` 和最终 plan 都成功。

## 清理

```powershell
terraform destroy -auto-approve
```

参考：[Providers within modules](https://developer.hashicorp.com/terraform/language/modules/develop/providers)、[`for_each` meta-argument](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each)。
