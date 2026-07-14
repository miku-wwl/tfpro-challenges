## Challenge 3.5 — LocalStack Community 版本

这是 Challenge 3 的 LocalStack 兼容版本。它保留了模块拆分、共享
credentials/config、多 Provider、定向部署和生命周期管理练习。由于 LocalStack
Community 不支持 Auto Scaling，原 ASG 资源由 `terraform_data` 容量控制器替代。

### 基础设施

开始任务 1 前，请在 `base-folder` 目录中执行：

```powershell
terraform init
terraform apply -auto-approve
```

这会在 LocalStack 中创建三个 IAM Role、两个用户及其 Access Key：

- `EC2FullAccessChallenge35`
- `IAMFullAccessChallenge35`
- `ReadOnlyRoleChallenge35`
- `kplabs-challenge35-user`
- `ro-user-challenge35`

### 任务

#### 1. 将资源拆分到子模块

将 `challenge-3.5.tf`（不是 `base-folder`）中的资源移动到 `modules`
目录下的子模块。

| 资源类型 | 子模块目录 |
| :--- | :---: |
| `aws_launch_template` | `compute` |
| `terraform_data` | `compute` |
| `aws_iam_user` | `iam` |
| `aws_iam_user_policy` | `iam` |

在根模块的 `challenge-3.5.tf` 中配置各子模块正确的 `source`。

#### 2. 创建共享 config 和 credentials 文件

在当前目录创建 `.aws/conf` 和 `.aws/credentials`。

- `conf` 中只能包含 `compute` 和 `iam` 两个 profile。
- 两个 profile 均使用 `us-east-1` Region。
- `compute` Assume `EC2FullAccessChallenge35`。
- `iam` Assume `IAMFullAccessChallenge35`。
- 两者都使用 `kplabs-challenge35-user` 的凭证作为源凭证。

#### 3. 添加 Provider 配置

- compute 子模块使用 `compute` profile。
- IAM 子模块使用 `iam` profile。
- `data.aws_caller_identity.local` 应使用 `ro-user-challenge35` 的凭证
  Assume `ReadOnlyRoleChallenge35`。
- 所有 AWS provider 配置都必须使用 LocalStack endpoint：
  `http://localhost:4566`。

#### 4. 部署资源

先只创建本地文件：

```powershell
terraform apply -target=local_file.this
```

确认 `account-number.txt` 已创建，且内容是 LocalStack Account ID：
`000000000000`。

然后部署其余资源：

```powershell
terraform apply -auto-approve
```

#### 5. 忽略 Desired Capacity 变更

将容量控制器的值从 `1` 改为 `2`。添加生命周期规则来忽略该值的变化。
后续 plan 不应更新该资源，state 中仍应保留初始值 `1`。

该任务替代原 Challenge 3 中 ASG 的 `desired_capacity` 练习，但保留相同的
Terraform 生命周期管理概念。

### 清理

完成后销毁根配置和 `base-folder` 中创建的资源：

```powershell
terraform destroy -auto-approve
Set-Location .\base-folder
terraform destroy -auto-approve
```
