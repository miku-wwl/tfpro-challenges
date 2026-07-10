# Challenge 1 解题教程

## 验证说明

本教程已使用 Terraform v1.14.0、AWS Provider v5.80.0、Random Provider v3.9.0 和 LocalStack Community v4.14.0 完整实测。实际覆盖 `init`、`validate`、`plan`、`apply`、output 写文件、删除 state、12 个 AWS 资源 import、`state rm`、零变更检查和 destroy。

实测结果：Task 1 创建 13 个 Terraform 实例；Task 5 重建后的 12 个 AWS 地址得到 `No changes`；Task 6 只新增 1 个对象；Task 7 移除两个 state 地址后仍为 `No changes` 且两个 `base.txt` 仍存在；Task 8 销毁 11 个受管实例，最终桶列表和 IAM 用户列表为空，安全组返回 `InvalidGroup.NotFound`。

LocalStack 的资源 ID、默认 VPC和 IAM 行为是模拟结果，真实 AWS 中的 ID 会不同；正式考试配置不能保留 LocalStack endpoint、测试凭证和跳过校验参数。另一个实测差异是 LocalStack `latest`（当时为 2026.6.2）无授权令牌会以 exit 55 退出，因此验证固定使用社区版 `4.14.0`。

## 题目目标

修复变量类型、`count`/`for_each` 和资源引用，创建 IAM、S3 与安全组资源；再练习 output、导入、移除 state 和销毁。关键要求是 Task 7 只解除 `base.txt` 的 Terraform 管理，不能当场删除云端对象。

## 开始前检查

先启动并检查本地实验环境：

```powershell
docker run -d --name challenge1-localstack -p 4566:4566 `
  -e SERVICES=s3,iam,ec2,sts localstack/localstack:4.14.0
docker ps --filter 'name=challenge1-localstack'
Invoke-RestMethod http://localhost:4566/_localstack/health
```

实验副本中的原 `provider "aws"` 需临时增加以下参数，不能再声明第二个默认 provider：

```hcl
provider "aws" {
  region                      = var.region
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam = "http://localhost:4566"
    s3  = "http://localhost:4566"
    ec2 = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}
```

正式考试中删除上述 LocalStack 专用参数，确认真实身份后再初始化：

```powershell
aws sts get-caller-identity
terraform version
terraform init
```

- 确认 AWS Profile/账号和区域是考试指定环境，不要在个人生产账号操作。
- 将 `tfvars.json` 中 `region` 改为区域名（例如 `us-east-1`），不能使用可用区 `us-east-1c`。
- Task 4 删除 state 前保存资源名和 ID；Task 7 的 `base.txt` 必须保留到 Task 8。

## Task 1：修复并部署代码

### 解题思路

- `list(strings)` 应为 `list(string)`，`environement` 的实际值是字符串。
- `sg_name` 被使用但未声明；provider 应使用 `var.region`。
- `for_each` 不能直接接收 list，使用 `toset` 后 `each.key`/`each.value` 都是桶后缀。
- 三个 IAM 用户各自需要策略，因此策略也使用 `count = 3`，并按索引引用用户。

在 `variables.tf` 中修复或补充：

```hcl
variable "environement" { type = string }
variable "s3_buckets" { type = list(string) }
variable "s3_base_object" { type = string }
variable "org-name" { type = string }
variable "region" { type = string }
variable "sg_name" { type = string }
```

在 `main.tf` 中进行最小修改：

```hcl
provider "aws" {
  region = var.region
  default_tags {
    tags = { Environment = var.environement }
  }
}

resource "aws_iam_user_policy" "lb_ro" {
  count = 3
  name  = "ec2-describe-policy"
  user  = aws_iam_user.lb[count.index].name
  # 原 policy = jsonencode(...) 保持不变
}

resource "aws_s3_bucket" "example" {
  for_each = toset(var.s3_buckets)
  bucket   = "${random_pet.this.id}-${each.value}"
}

resource "aws_s3_object" "object" {
  for_each = toset(var.s3_buckets)
  bucket   = aws_s3_bucket.example[each.key].id
  key      = var.s3_base_object
}
```

把 `tfvars.json` 的 region 改为 `us-east-1`，然后执行：

```powershell
terraform fmt -recursive
terraform validate
terraform plan '-var-file=tfvars.json'
terraform apply '-var-file=tfvars.json'
terraform state list
```

预期 state 共 13 个地址；其中包括 `aws_iam_user.lb[0..2]`、三个策略实例、两个桶、两个 `base.txt` 对象、安全组、规则和 `random_pet.this`。PowerShell 中将含 `[]` 或引号的资源地址整体放进单引号。

难点入口：搜索 `Terraform count index resource`、`Terraform for_each toset`；官网：[count](https://developer.hashicorp.com/terraform/language/meta-arguments/count)、[for_each](https://developer.hashicorp.com/terraform/language/meta-arguments/for_each)。

## Task 2：输出资源值

在新建的 `outputs.tf` 中添加：

```hcl
output "s3_buckets" {
  value = [for bucket in aws_s3_bucket.example : bucket.id]
}

output "user_names" {
  value = aws_iam_user.lb[*].name
}

output "sg_id" {
  value = aws_security_group.example.id
}

output "sg_rule_id" {
  value = aws_vpc_security_group_ingress_rule.example.id
}
```

```powershell
terraform fmt
terraform validate
terraform output
```

预期得到 2 个桶名、3 个用户名、1 个 `sg-...` 和 1 个 `sgr-...`。官网：[Output values](https://developer.hashicorp.com/terraform/language/values/outputs)。

## Task 3：将 output 保存到文件

仍在 `challenge-1` 执行；`-json` 能为列表保留完整结构：

```powershell
terraform output -json s3_buckets | Set-Content -Encoding utf8 s3.txt
terraform output -json user_names | Set-Content -Encoding utf8 iam-users.txt
terraform output -raw sg_id | Set-Content -Encoding utf8 sg-combined.txt
terraform output -raw sg_rule_id | Add-Content -Encoding utf8 sg-combined.txt
Get-Content s3.txt, iam-users.txt, sg-combined.txt
```

预期前两个文件分别含 2 个桶名和 3 个用户名，`sg-combined.txt` 含两行 ID。

## Task 4：删除安全组配置和本地 state

这是危险操作。先记录所有资源标识并备份 state 和输出文件：

```powershell
terraform state pull | Set-Content -Encoding utf8 state-before-delete.json
terraform state list | Set-Content -Encoding utf8 addresses-before-delete.txt
terraform output -json | Set-Content -Encoding utf8 outputs-before-delete.json
```

从 `main.tf` 删除 `aws_security_group.example` 和 `aws_vpc_security_group_ingress_rule.example` 两个 block；同时暂时从 `outputs.tf` 删除 `sg_id`、`sg_rule_id`，否则配置引用不存在的资源而无法验证。然后删除本地 state：

```powershell
Remove-Item -LiteralPath terraform.tfstate -ErrorAction SilentlyContinue
Remove-Item -LiteralPath terraform.tfstate.backup -ErrorAction SilentlyContinue
terraform validate
```

不要先运行 `terraform apply`，否则其余现存资源会因 state 为空而被计划重复创建。

## Task 5：导入所有资源到新 state

### 导入前准备

先把 Task 4 删除的两个安全组 block 和两个 output 恢复，使配置覆盖 Task 1 创建的全部 AWS 资源。通过 `outputs-before-delete.json`、`state-before-delete.json` 或 AWS CLI 查出以下占位值：

- `<PET_ID>`：所有桶/用户名称共同的随机前缀；
- `<USER_0>`～`<USER_2>`、`<BUCKET_1>`、`<BUCKET_2>`；
- `<SG_ID>` 和 `<SG_RULE_ID>`。

`random_pet.this` 在 Random Provider v3.9.0 中不支持 import，实测会报 `Resource Import Not Implemented`。如果保留它而直接导入 AWS 资源，下次 plan 会生成新随机前缀并计划替换用户名和桶名。

因此在 Task 5 中移除 `random_pet.this`，新增固定前缀变量，并将两个名称表达式中的 `random_pet.this.id` 改为 `var.pet_id`：

```hcl
variable "pet_id" {
  type = string
}

resource "aws_iam_user" "lb" {
  count = 3
  name  = "${var.pet_id}-${var.org-name}-${count.index}"
}

resource "aws_s3_bucket" "example" {
  for_each = toset(var.s3_buckets)
  bucket   = "${var.pet_id}-${each.value}"
}
```

在 `tfvars.json` 中加入实际记录的前缀，例如 `"pet_id": "<PET_ID>"`，然后导入 12 个 AWS 资源：

```powershell
terraform import '-var-file=tfvars.json' 'aws_iam_user.lb[0]' '<USER_0>'
terraform import '-var-file=tfvars.json' 'aws_iam_user.lb[1]' '<USER_1>'
terraform import '-var-file=tfvars.json' 'aws_iam_user.lb[2]' '<USER_2>'
terraform import '-var-file=tfvars.json' 'aws_iam_user_policy.lb_ro[0]' '<USER_0>:ec2-describe-policy'
terraform import '-var-file=tfvars.json' 'aws_iam_user_policy.lb_ro[1]' '<USER_1>:ec2-describe-policy'
terraform import '-var-file=tfvars.json' 'aws_iam_user_policy.lb_ro[2]' '<USER_2>:ec2-describe-policy'
terraform import '-var-file=tfvars.json' 'aws_s3_bucket.example["kplabs-1"]' '<BUCKET_1>'
terraform import '-var-file=tfvars.json' 'aws_s3_bucket.example["kplabs-2"]' '<BUCKET_2>'
terraform import '-var-file=tfvars.json' 'aws_s3_object.object["kplabs-1"]' '<BUCKET_1>/base.txt'
terraform import '-var-file=tfvars.json' 'aws_s3_object.object["kplabs-2"]' '<BUCKET_2>/base.txt'
terraform import '-var-file=tfvars.json' aws_security_group.example '<SG_ID>'
terraform import '-var-file=tfvars.json' aws_vpc_security_group_ingress_rule.example '<SG_RULE_ID>'
```

导入 ID 若因 provider 版本或真实 AWS 返回格式报错，应先查看相应 Registry 页，不要猜测后继续 apply。验证：

```powershell
terraform state list
terraform plan '-var-file=tfvars.json'
```

目标是 12 个 AWS 地址且 `No changes`（等价于 0 add、0 change、0 destroy）。若 plan 显示新建 `random_pet.this`、替换或销毁，说明固定前缀重构未完成，禁止 apply。

难点入口：搜索 `Terraform import for_each PowerShell`、`Terraform aws iam user policy import`、`Terraform aws s3 object import`；官网：[Import resources](https://developer.hashicorp.com/terraform/cli/import)、[AWS Provider 文档](https://registry.terraform.io/providers/hashicorp/aws/5.80.0/docs)。

## Task 6：创建 `new.txt`

题目要求创建一个对象；下面选择变量列表中的第一个桶。在 `main.tf` 添加：

```hcl
resource "aws_s3_object" "new" {
  bucket  = aws_s3_bucket.example[var.s3_buckets[0]].id
  key     = "new.txt"
  content = "Success"
}
```

```powershell
terraform fmt
terraform validate
terraform plan '-var-file=tfvars.json'
terraform apply '-var-file=tfvars.json'
terraform state show aws_s3_object.new
```

预期 plan 只新增一个对象，state 中 `key = "new.txt"`、`content = "Success"`。

## Task 7：从配置和 state 移除 `base.txt`

先备份 state。这里有两个 `for_each` 实例，必须全部移除；`state rm` 只解除管理，不删除 AWS 对象：

```powershell
terraform state pull | Set-Content -Encoding utf8 state-before-base-rm.json
terraform state list | Select-String 'aws_s3_object.object'
```

从 `main.tf` 删除整个 `aws_s3_object.object` block，然后执行：

```powershell
terraform state rm 'aws_s3_object.object["kplabs-1"]'
terraform state rm 'aws_s3_object.object["kplabs-2"]'
terraform state list
terraform plan '-var-file=tfvars.json'
aws s3api head-object --bucket '<BUCKET_1>' --key 'base.txt'
aws s3api head-object --bucket '<BUCKET_2>' --key 'base.txt'
```

预期两个地址不在 state，plan 为 `No changes`，但两次 `head-object` 都成功。**此时不要执行 `terraform destroy` 前的普通 apply，也不要用 AWS CLI 删除 base 对象。**

难点入口：搜索 `Terraform state rm for_each`；官网：[terraform state rm](https://developer.hashicorp.com/terraform/cli/commands/state/rm)。

## Task 8：销毁全部资源

Task 7 保留下来的两个 `base.txt` 已不受 Terraform 管理，而且非空桶通常无法删除。Task 8 已明确要求销毁本 Challenge 创建的全部资源，因此先确认账号与桶名，再删除这两个遗留对象，最后 destroy：

```powershell
aws sts get-caller-identity
aws s3api delete-object --bucket '<BUCKET_1>' --key 'base.txt'
aws s3api delete-object --bucket '<BUCKET_2>' --key 'base.txt'
terraform plan -destroy '-var-file=tfvars.json'
terraform destroy '-var-file=tfvars.json'
terraform state list
```

预期 destroy 删除 Terraform 仍管理的 `new.txt`、两个桶、IAM 用户及策略、安全组和规则，共 11 个实例；最终 `terraform state list` 为空。再检查遗留资源：

```powershell
aws s3api head-bucket --bucket '<BUCKET_1>'
aws s3api head-bucket --bucket '<BUCKET_2>'
aws iam get-user --user-name '<USER_0>'
aws ec2 describe-security-groups --group-ids '<SG_ID>'
```

这些命令应返回不存在/找不到资源。若 destroy 因 IAM 策略或 S3 对象残留失败，查看报错并清理本 Challenge 对象后重试，不要删除无关资源。

## 最终检查

- Task 1 的 `validate` 通过，初始资源实例数为 13。
- 四个 output 的数量和 ID 类型正确，三个文件内容完整。
- 重建 state 后全部 12 个 AWS 地址存在，且 plan 为零变更；配置中已不再保留无法导入的 `random_pet.this`。
- Task 6 只新增一个内容为 `Success` 的 `new.txt`。
- Task 7 后两个 `base.txt` 不在 state、仍存在于 AWS，plan 为零变更。
- Task 8 后 state 为空，两个桶、三个用户和安全组均不存在。
