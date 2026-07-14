## Challenge 2

本挑战要求将单体 Terraform 配置重构为多个子模块，以考查你对 Terraform Module 的理解。

### 任务

#### 1. 部署资源

运行 `terraform apply -auto-approve` 部署所有资源。

☆
#### 2. 使用 Data Source 替换硬编码值

使用 `aws_ami` data source 替换 `aws_instance` 资源中硬编码的 AMI ID，并动态获取该值。

> [!CAUTION]
> 不得重新创建 EC2 实例，并且必须继续使用与步骤 1 相同的 AMI ID。

☆
#### 3. 拆分为多个模块

按照下表将现有代码拆分（移动）到多个子模块。所有子模块都必须位于 `modules` 目录中。

| 资源 | 子模块目录名 |
| :--- | :---: |
| `aws_instance`、`aws_ami` | ec2 |
| `aws_security_group` | sg |
| `aws_vpc_security_group_ingress_rule` | sg |
| `aws_s3_bucket` | s3 |
| `aws_s3_object` | s3 |
| `aws_iam_*` | iam |
| `random_pet` | random |

* 不要修改已经移动到子模块中的主要资源配置代码（仅限本任务）。
* 在根模块的 `main.tf` 中配置正确的 module source，以加载所有子模块。
* 在子模块中添加适当的变量。
* 在根模块中传入适当的变量值。
* 运行 `terraform init` 重新初始化，并确保没有错误。

#### 4. 临时添加硬编码值

对于原先使用字符串插值获取 `random_pet` 值的位置，注释现有参数，并手动填入 state 文件中的 `random_pet` 实际值。

示例：

```sh
# 替换此配置：
test = "${random_pet.name}"

# 改为：
test = "hardcoded-value-from-state"
```

对于 EC2 实例，手动填入 state 文件中的最终 `instance_profile` 值，并注释之前的参数。

运行 `terraform plan` 时必须没有错误。

#### 5. 调整资源地址

更新 state 文件中的资源地址，使其反映从单体配置重构为多个子模块后的地址。

完成上一步后运行 `terraform plan`，确保没有任何变更：

```sh
Plan: 0 to add, 0 to change, 0 to destroy.
```

同时确保没有与 `Value for undeclared variable` 有关的警告。

#### 6. 实现动态值

删除步骤 4 中添加的临时硬编码值，并实现正确的模块输出：

* EC2 模块：能够从 IAM 模块获取 `iam_instance_profile`。
* IAM 模块：能够从 random 模块获取 `random_pet` 值。
* S3 模块：能够从 random 模块获取 `random_pet` 值。
* 必须删除步骤 4 添加的硬编码值。

运行 `terraform apply` 并确保没有任何变更。

#### 7. 销毁基础设施

运行 `terraform destroy -auto-approve` 销毁所有已创建的基础设施。
