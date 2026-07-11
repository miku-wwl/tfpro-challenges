# Challenge 2 解题教程

## 验证说明

本教程已使用 Terraform v1.14.0、AWS Provider v5.80.0、Random Provider v3.9.0、Docker 29.4.3 和 LocalStack Community v4.14.0 完整实测。实际执行了创建、AMI data source 替换、模块拆分、18 条模块地址检查、`state mv`、动态模块输出、零变更 apply 和 destroy。

实测结果：Task 1 创建 16 个资源；Task 2 替换为 data source 后 EC2 实例 ID 不变；Task 5 和 Task 6 均得到 `No changes`；Task 7 销毁 16 个资源，最终 S3 桶、IAM 用户和运行中 EC2 实例列表均为空。

LocalStack 允许使用不存在的 AMI ID创建实例，但 `aws_ami` 无法查询该 ID。实验中先用 `register-image` 注册了可查询 AMI，再验证“硬编码 ID → data source”不会重建。真实 AWS 应直接为题目 AMI选择能唯一返回同一 ID 的过滤条件，不能照抄实验 AMI ID。

## 题目目标

先部署单体配置，并在不重建 EC2 的前提下用 `aws_ami` 替换硬编码。随后把资源拆入五个子模块，通过 `state mv` 保留现有资源，最后用模块输入输出替换临时硬编码并完成零变更验收。

## 开始前检查

本地实验可启动独立 LocalStack；如果 4566 已占用，可像本次实测一样改用宿主机 4567：

```powershell
docker run -d --name challenge2-localstack -p 4567:4566 `
  -e SERVICES=s3,iam,ec2,sts localstack/localstack:4.14.0
docker ps --filter 'name=challenge2-localstack'
Invoke-RestMethod http://localhost:4567/_localstack/health
```

仅在实验副本中，把原有默认 AWS provider 改为 LocalStack 配置；不要再增加第二个默认 provider：

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
    iam = "http://localhost:4567"
    s3  = "http://localhost:4567"
    ec2 = "http://localhost:4567"
    sts = "http://localhost:4567"
  }
}
```

正式考试配置必须删除测试凭证、endpoint 和跳过校验参数，并先确认身份：

```powershell
Set-Location challenge-2
aws sts get-caller-identity
terraform init
terraform validate
```

## Task 1：部署资源

原题配置可以直接创建 16 个资源；`s3_buckets` 已声明为 `set(string)`，可直接用于 `for_each`。执行：

```powershell
terraform fmt -recursive
terraform init
terraform validate
terraform apply -auto-approve '-var-file=terraform.tfvars.json'
terraform state list
```

预期有 16 个 resource 地址和一个 `data.aws_iam_policy_document.assume_role` 地址，包括 1 个实例、2 个桶、2 个对象、3 个用户、3 个用户策略、IAM role/profile、安全组/规则和 random pet。先保存关键值，供 Task 4 使用：

```powershell
terraform state show random_pet.this
terraform state show aws_iam_instance_profile.test_profile
terraform state show aws_instance.this
```

记录 `<PET_ID>`、instance profile 的 `name` 和 EC2 的 `id`、`ami`。

## Task 2：用 AMI data source 替换硬编码

### 解题思路

过滤条件必须唯一命中 Task 1 使用的同一 AMI。先在真实 AWS 查询该 AMI 的 owner、name、architecture 等属性，再选择稳定条件；修改后必须比较实例 ID，并确认 plan 没有 `-/+` replacement。

在根目录 `main.tf` 添加 data source。下面的 owner/name 是写法示例，必须替换成 Task 1 AMI 的真实属性：

```hcl
data "aws_ami" "this" {
  most_recent = true
  owners      = ["<AMI_OWNER_ID>"]

  filter {
    name   = "name"
    values = ["<AMI_NAME_OR_PATTERN>"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
```

将实例中的硬编码替换为：

```hcl
resource "aws_instance" "this" {
  ami                  = data.aws_ami.this.id
  instance_type        = "t2.micro"
  iam_instance_profile = aws_iam_instance_profile.test_profile.name
}
```

验证 data source 与 state 中原 AMI完全相同：

```powershell
terraform console '-var-file=terraform.tfvars.json'
```

在 console 中输入 `data.aws_ami.this.id`，退出后执行：

```powershell
terraform plan '-var-file=terraform.tfvars.json'
terraform state show aws_instance.this
```

预期 `No changes`，且 EC2 的 `id` 与 Task 1 相同。若 AMI不同，立即调整过滤条件，禁止 apply。

LocalStack 4.14.0 实验需先注册可查询 AMI：

```powershell
$env:AWS_ACCESS_KEY_ID='test'
$env:AWS_SECRET_ACCESS_KEY='test'
$env:AWS_DEFAULT_REGION='us-east-1'
aws --endpoint-url=http://localhost:4567 ec2 register-image `
  --name challenge2-ami --architecture x86_64 `
  --root-device-name /dev/sda1 --virtualization-type hvm
```

把返回的 `<LOCALSTACK_AMI_ID>` 作为实验基线硬编码 apply 一次，再用 `filter { name = "image-id" ... }` 查询同一 ID；实测替换后 plan 为零变更、实例 ID 不变。这个适配只用于 LocalStack。

难点入口：搜索 `Terraform aws_ami data source filters`；官网：[AWS Provider aws_ami data source](https://registry.terraform.io/providers/hashicorp/aws/5.80.0/docs/data-sources/ami)。

## Task 3：拆分为五个子模块

创建以下目录；资源 block 原样移动，暂不改变其业务参数：

```text
modules/
├── ec2/       # data.aws_ami.this、aws_instance.this
├── iam/       # data.aws_iam_policy_document 和所有 aws_iam_*
├── random/    # random_pet.this
├── s3/        # aws_s3_bucket、aws_s3_object
└── sg/        # aws_security_group、ingress rule
```

每个模块至少包含 `main.tf`；需要输入的模块增加 `variables.tf`：

```hcl
# modules/iam/variables.tf
variable "org-name" { type = string }

# modules/s3/variables.tf
variable "s3_buckets" { type = set(string) }
variable "s3_base_object" { type = string }

# modules/sg/variables.tf
variable "sg_name" { type = string }
```

根模块的资源 block 移走后，在 `main.tf` 添加调用：

```hcl
module "random" { source = "./modules/random" }

module "iam" {
  source   = "./modules/iam"
  org-name = var.org-name
}

module "s3" {
  source         = "./modules/s3"
  s3_buckets     = var.s3_buckets
  s3_base_object = var.s3_base_object
}

module "sg" {
  source  = "./modules/sg"
  sg_name = var.sg_name
}

module "ec2" { source = "./modules/ec2" }
```

此时跨模块直接引用还没有解决，Task 3 只要求重新加载本地模块：

```powershell
terraform fmt -recursive
terraform init -reconfigure
```

预期显示 `Initializing modules...`，五个模块均成功加载。

## Task 4：临时使用 state 中的硬编码

不同模块不能直接引用另一个模块内部的资源。在移动后的代码中注释原表达式，并使用 Task 1 记录的实际值：

```hcl
# modules/iam/main.tf
# name = "${random_pet.this.id}-${var.org-name}-${count.index}"
name = "<PET_ID>-${var.org-name}-${count.index}"

# modules/s3/main.tf
# bucket = "${random_pet.this.id}-${each.value}"
bucket = "<PET_ID>-${each.value}"

# modules/ec2/main.tf
# iam_instance_profile = aws_iam_instance_profile.test_profile.name
iam_instance_profile = "<INSTANCE_PROFILE_NAME>"
```

```powershell
terraform validate
terraform plan '-var-file=terraform.tfvars.json'
```

此时 plan 显示旧根地址 destroy、新模块地址 create 是正常的；不要 apply。硬编码值必须与 state 完全一致，否则 Task 5 无法得到零变更。

## Task 5：迁移 state 地址

这是危险操作。先备份并查看实际地址：

```powershell
terraform state pull | Set-Content -Encoding utf8 state-before-module-mv.json
terraform state list
```

按资源表执行迁移。PowerShell 中含索引的地址用单引号包住，并用 `\"` 保留 `for_each` 的字符串引号：

```powershell
terraform state mv random_pet.this module.random.random_pet.this
terraform state mv aws_instance.this module.ec2.aws_instance.this

terraform state mv data.aws_iam_policy_document.assume_role module.iam.data.aws_iam_policy_document.assume_role
terraform state mv aws_iam_role.test_role module.iam.aws_iam_role.test_role
terraform state mv aws_iam_instance_profile.test_profile module.iam.aws_iam_instance_profile.test_profile
terraform state mv 'aws_iam_user.lb[0]' 'module.iam.aws_iam_user.lb[0]'
terraform state mv 'aws_iam_user.lb[1]' 'module.iam.aws_iam_user.lb[1]'
terraform state mv 'aws_iam_user.lb[2]' 'module.iam.aws_iam_user.lb[2]'
terraform state mv 'aws_iam_user_policy.lb_ro[0]' 'module.iam.aws_iam_user_policy.lb_ro[0]'
terraform state mv 'aws_iam_user_policy.lb_ro[1]' 'module.iam.aws_iam_user_policy.lb_ro[1]'
terraform state mv 'aws_iam_user_policy.lb_ro[2]' 'module.iam.aws_iam_user_policy.lb_ro[2]'

terraform state mv 'aws_s3_bucket.example[\"kplabs-1\"]' 'module.s3.aws_s3_bucket.example[\"kplabs-1\"]'
terraform state mv 'aws_s3_bucket.example[\"kplabs-2\"]' 'module.s3.aws_s3_bucket.example[\"kplabs-2\"]'
terraform state mv 'aws_s3_object.object[\"kplabs-1\"]' 'module.s3.aws_s3_object.object[\"kplabs-1\"]'
terraform state mv 'aws_s3_object.object[\"kplabs-2\"]' 'module.s3.aws_s3_object.object[\"kplabs-2\"]'

terraform state mv aws_security_group.example module.sg.aws_security_group.example
terraform state mv aws_vpc_security_group_ingress_rule.example module.sg.aws_vpc_security_group_ingress_rule.example
```

`data.aws_ami.this` 只有在 `terraform state list` 中实际存在才迁移：

```powershell
terraform state mv data.aws_ami.this module.ec2.data.aws_ami.this
```

本次实测在 Task 2 只运行 plan 时，该 data 地址没有持久化，执行上面命令会报 `does not match anything`；跳过即可，模块内 data source 会在下一次 plan 重新读取。

最后检查：

```powershell
terraform state list
terraform plan '-var-file=terraform.tfvars.json'
```

预期所有地址都有 `module.<name>.` 前缀，且结果为 `No changes`。输出中不能出现 `Value for undeclared variable`；若出现，检查根 `variables.tf` 是否声明了 `terraform.tfvars.json` 中的所有键。

难点入口：搜索 `Terraform state mv child module for_each PowerShell`；官网：[terraform state mv](https://developer.hashicorp.com/terraform/cli/commands/state/mv)、[Refactoring modules](https://developer.hashicorp.com/terraform/language/modules/develop/refactoring)。

## Task 6：用模块 outputs 恢复动态引用

Random 模块输出 pet ID：

```hcl
# modules/random/outputs.tf
output "pet_id" {
  value = random_pet.this.id
}
```

IAM 模块新增 `random_pet_id` 输入，用它恢复用户名表达式，并输出 profile 名：

```hcl
# modules/iam/variables.tf
variable "random_pet_id" { type = string }

# modules/iam/main.tf
name = "${var.random_pet_id}-${var.org-name}-${count.index}"

# modules/iam/outputs.tf
output "instance_profile_name" {
  value = aws_iam_instance_profile.test_profile.name
}
```

S3 与 EC2 模块分别新增输入并删除硬编码：

```hcl
# modules/s3/variables.tf
variable "random_pet_id" { type = string }

# modules/s3/main.tf
bucket = "${var.random_pet_id}-${each.value}"

# modules/ec2/variables.tf
variable "iam_instance_profile" { type = string }

# modules/ec2/main.tf
iam_instance_profile = var.iam_instance_profile
```

根模块传递模块输出：

```hcl
module "iam" {
  source        = "./modules/iam"
  org-name      = var.org-name
  random_pet_id = module.random.pet_id
}

module "s3" {
  source         = "./modules/s3"
  s3_buckets     = var.s3_buckets
  s3_base_object = var.s3_base_object
  random_pet_id  = module.random.pet_id
}

module "ec2" {
  source               = "./modules/ec2"
  iam_instance_profile = module.iam.instance_profile_name
}
```

```powershell
terraform fmt -recursive
terraform validate
terraform plan '-var-file=terraform.tfvars.json'
terraform apply -auto-approve '-var-file=terraform.tfvars.json'
```

预期 plan 为 `No changes`，apply 显示 `0 added, 0 changed, 0 destroyed`。模块引用也会自动建立 `random → iam/s3` 和 `iam → ec2` 的依赖关系。

难点入口：搜索 `Terraform child module output input`；官网：[Module composition](https://developer.hashicorp.com/terraform/language/modules/develop/composition)、[Output values](https://developer.hashicorp.com/terraform/language/values/outputs)。

## Task 7：销毁基础设施

先确认销毁计划只包含本 Challenge 的 16 个资源：

```powershell
terraform plan -destroy '-var-file=terraform.tfvars.json'
terraform destroy -auto-approve '-var-file=terraform.tfvars.json'
terraform state list
```

预期销毁 16 个资源且 state 为空。真实 AWS 中再检查遗留对象：

```powershell
aws s3api list-buckets
aws iam list-users
aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping,stopped
```

只核对并清理由本 Challenge 创建的名称/ID，不要删除其他资源。

## 最终检查

- Task 1 的 16 个资源创建成功，关键 state 值已记录。
- `aws_ami` 返回与原配置相同的 AMI，EC2 实例没有重建。
- 五个子模块均位于 `modules` 下并能被 `terraform init` 加载。
- `state mv` 后所有资源位于对应模块地址，plan 为零变更。
- 没有 `Value for undeclared variable` 警告。
- 临时随机前缀和 instance profile 硬编码已全部删除。
- Task 6 的 plan/apply 都是零变更。
- Task 7 后 state 为空，S3、IAM 与 EC2 无本 Challenge 遗留资源。
