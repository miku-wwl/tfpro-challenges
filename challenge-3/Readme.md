## Challenge 3

本挑战重点考查如何在 Terraform Module 中使用 AWS 服务实现多 Provider 配置。

### 基础任务

`base-folder` 中配置了以下重要资源代码：

| 资源代码 | 说明 |
| :--- | :---: |
| `EC2FullAccess` IAM Role | 提供对 EC2 服务的完全访问权限。 |
| `IAMFullAccess` IAM Role | 提供对 IAM 服务的完全访问权限。 |
| `ReadOnlyRole` IAM Role | 提供对所需服务的只读权限。 |
| `kplabs-challenge3-user` | 能够在 AWS 账户中 Assume `EC2FullAccess` 和 `IAMFullAccess` Role。 |
| `ro-user` | 能够在 AWS 账户中 Assume `ReadOnlyRole` IAM Role。 |

在开始任务 1 之前，运行 `terraform apply -auto-approve` 创建所需资源。

### 任务

#### 1. 将资源拆分到子模块

按照下表，将 `challenge-3.tf`（不是 base-folder）中的资源拆分（移动）到子模块。所有子模块都必须位于 `modules` 目录中。

| 资源类型 | 子模块目录 |
| :--- | :---: |
| `aws_launch_template` | asg |
| `aws_autoscaling_group` | asg |
| `aws_iam_user` | iam |
| `aws_iam_user_policy` | iam |

在根模块的 `challenge-3.tf` 中配置正确的 module source，以加载所有子模块。

#### 2. 创建共享 Config 和 Credentials 文件

为本项目配置共享的 AWS credentials 和 config 文件。

* `conf` 和 `credentials` 文件必须位于 `challenge-3/.aws` 目录中。
* config 文件只能包含 `[asg]` 和 `[iam]` 两个 profile，不能包含 default 或其他 profile。
* 两个 profile 均使用 `us-east-1` Region。
* `./aws/conf` 中的 `[asg]` 和 `[iam]` profile 必须按以下要求指向 base-folder 创建的正确 IAM Role：

```text
[asg] profile 应指向名为 `EC2FullAccess` 的 IAM Role ARN
[iam] profile 应指向名为 `IAMFullAccess` 的 IAM Role ARN
```

* `[asg]` 和 `[iam]` profile 必须使用 base-folder 中 `kplabs-challenge3-user` 的凭证来 Assume 所需 Role。

#### 3. 添加正确的 Provider 配置

* ASG 子模块必须使用 `[asg]` profile。
* IAM 子模块必须使用 `[iam]` profile。
* `data.aws_caller_identity.local` 必须 Assume `ReadOnlyRole` 来获取数据，可使用 `ro-user` 的凭证进行身份验证。

#### 4. 部署资源

先运行 `terraform apply` 部署 `local_file` 资源，此时不应创建其他资源。确认包含账户编号的 `txt` 文件已成功创建。

然后运行 `terraform apply -auto-approve` 创建所有其他资源。

#### 5. 阻止 Desired Capacity 变更

将 Terraform 代码中的 `desired_capacity` 从 `1` 改为 `2`。

添加适当配置以忽略对 `desired_capacity` 的任何变更，使实际运行的 EC2 实例数量仍与基础代码一样保持为 `1`。

应用解决方案后，再尝试修改 ASG 资源的 capacity，确认 Terraform 是否计划更新实际资源。

### 销毁基础设施

删除本实验中创建的所有基础设施。
