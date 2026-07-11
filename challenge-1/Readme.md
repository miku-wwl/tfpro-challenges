## Challenge 1

本挑战通过修复错误代码、导入资源、输出值以及管理 Terraform 状态，考查你对 Terraform 的理解。

本挑战共包含 8 个任务。

### 任务

#### 1. 修复错误代码

本目录中提供的 Terraform 代码存在语法错误、资源配置错误或其他问题。你需要修复这些问题并成功部署资源。

#### 2. 输出值

使用 Terraform 的 `output` 块在 CLI 中显示以下值：

* S3 Bucket 名称列表。
* IAM 用户名列表。
* Security Group ID。
* Security Group Rule ID。

输出格式应与下面的示例类似，实际值可以不同。

```sh
   s3_buckets = [
      + "fancy-mouse-kplabs-1",
      + "fancy-mouse-kplabs-2",
    ]

   sg_id      = "sg-05da12b59833d3732"
   sg_rule_id = "sgr-009eccddbf2a81873"

   user_names = [
      + "fancy-mouse-var.org-name-0",
      + "fancy-mouse-var.org-name-1",
      + "fancy-mouse-var.org-name-2",
    ]
```

#### 3. 将输出值保存到文件

按照下表将输出值保存到对应文件：

| 对象的输出值 | 文件名 |
| :--- | :---: |
| S3 Bucket 名称 | s3.txt |
| IAM 用户名 | iam-users.txt |
| Security Group ID | sg-combined.txt |
| VPC Ingress Rule ID | sg-combined.txt |

#### 4. 删除资源配置和文件

* 从 Terraform 配置中删除与 `aws_security_group` 和 `aws_vpc_security_group_ingress_rule` 资源类型有关的代码。
* 删除 `terraform.tfstate` 文件及其备份文件 `terraform.tfstate.backup`（如果存在）。

#### 5. 导入所有资源

* 将步骤 1 中创建的所有 AWS 资源导入新的 Terraform state 文件。
* 确保现有 Terraform 配置与 AWS 中的实际资源一致，并且不会删除任何实际资源。

#### 6. 创建新资源

* 使用 `aws_s3_object` 在 S3 Bucket 中创建一个新对象。
* 对象名称必须为 `new.txt`。
* 对象内容必须为 `Success`。

#### 7. 从 State 中移除对象

* 从 Terraform 代码和 state 文件中移除步骤 1 创建的 S3 对象 `base.txt`。
* 确保该对象不会从 AWS 中删除。

> [!CAUTION]
> 不得删除之前创建的 S3 对象 `base.txt`，否则会被扣分。

#### 8. 销毁所有资源

销毁本 Challenge 1 中创建的所有资源。
