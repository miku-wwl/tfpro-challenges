## Challenge 6

本挑战重点考查多 Provider 配置以及你对 AWS Provider 的理解。

### 基础任务

`base-folder` 中配置了以下重要资源代码：

| 资源代码 | 说明 |
| :--- | :---: |
| `EC2FullAccess` IAM Role | 提供对 EC2 服务的完全访问权限。 |
| `IAMFullAccess` IAM Role | 提供对 IAM 服务的完全访问权限。 |
| `ReadOnlyRole` IAM Role | 提供对所需服务的只读权限。 |
| `default-profile-user` | 能够在 AWS 账户中 Assume `ReadOnlyRole` IAM Role。 |
| `kplabs-ec2-user` | 能够在 AWS 账户中 Assume `EC2FullAccess` IAM Role。 |
| `kplabs-iam-user` | 能够在 AWS 账户中 Assume `IAMFullAccess` IAM Role。 |

进入 base-folder 并运行 `terraform apply -auto-approve` 创建所需资源，然后再开始任务 1。

### 任务

### 1. 创建 AWS Config 文件

在 `./aws/config` 中创建以下 3 个 profile：

```sh
readonly-access
iam-access
ec2-access
```

三个 profile 都应包含以下配置：

```sh
region=us-east-1
output=text
```

* `iam-access` profile 应 Assume base-folder 创建的 `IAMFullAccess` IAM Role。
* `ec2-access` profile 应 Assume base-folder 创建的 `EC2FullAccess` IAM Role。
* `readonly-access` profile 应 Assume base-folder 创建的 `ReadOnlyRole` IAM Role。

### 2. 创建 AWS Credentials 文件

`./aws/credentials` 文件必须只包含以下两个 profile 的凭证：

```sh
[iam-access]
aws_access_key_id=ACCESS-KEY-HERE
aws_secret_access_key=SECRET-KEY-HERE

[ec2-access]
aws_access_key_id=ACCESS-KEY-HERE
aws_secret_access_key=SECRET-KEY-HERE
```

`[iam-access]` profile 的 Access/Secret Key 应来自 base-folder 创建的 IAM 用户 `kplabs-iam-user`。

`[ec2-access]` profile 的 Access/Secret Key 应来自 base-folder 创建的 IAM 用户 `kplabs-ec2-user`。

### 3. 添加 Source Profile

`readonly-access` profile 应使用 `default` profile 的凭证来 Assume 所需 Role。为该 profile 添加必要参数以实现此要求。

不得在 challenge-6 目录的 `./aws/config` 或 `./aws/credentials` 中添加 `[default]` profile。

`default` profile 的凭证位于 base-folder 的 `default-creds.txt` 文件中。

> [!NOTE]
> 术语说明：`readonly-access`、`iam-access` 和 `ec2-access` 是 AWS CLI
> profile 名称，不是 IAM User 或 IAM Role。`source_profile` 指向提供长期
> Access Key/Secret Key 的来源 profile；`role_arn` 指向要 Assume 的目标 IAM Role。
>
> 本实验中，`readonly-access` 使用 `default` profile 的凭证来 Assume
> `ReadOnlyRole`。`default` 的凭证来自 `base-folder/default-creds.txt`，并不表示
> `default` 去 Assume `readonly-access`。实际考试中应以题目给出的凭证与 profile
> 关系为准，不要自行假设 profile 名称或 IAM User 的对应关系。

### 4. 修改 `challenge-6.tf`

* `aws_iam_role` 资源类型必须使用 `[iam-access]` profile。
* `aws_security_group` 资源类型必须使用 `[ec2-access]` profile。
* `aws_caller_identity` data source 应使用 `readonly-access` profile 中的信息向 AWS 发出请求。

> [!TIP]
> 对于 `readonly-access` profile 的相关配置，可以从 `.aws/config` 和 `default-creds.txt` 获取全部必要信息，并直接添加到 `provider` block 中，而不是引用这些文件。

### 5. 应用变更

运行 `terraform apply -auto-approve`，确保成功创建所有资源。

### 6. 移除弃用警告

移除代码或输出中出现的所有 deprecated 警告。

### 7. 销毁基础设施

删除本实验中创建的所有基础设施。
