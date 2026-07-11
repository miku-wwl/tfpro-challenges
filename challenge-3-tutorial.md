# Challenge 3 解题教程

## 验证说明

本教程使用 Terraform v1.14.0、AWS Provider v5.80.0、Local Provider v2.9.0、Docker 29.4.3 和 LocalStack Community v4.14.0 实测。已实际完成：部署 base-folder 的 14 个 IAM 资源、生成两组 access key、建立共享 profile/role 链、用 ReadOnlyRole 创建账号文件、通过不同 provider 创建 IAM 用户和 launch template，以及按正确顺序销毁。

实测 caller ARN 分别为 `assumed-role/EC2FullAccess/...`、`assumed-role/IAMFullAccess/...` 和 `assumed-role/ReadOnlyRole/...`，证明三个身份链有效。LocalStack Community v4.14.0 的 Auto Scaling API 返回 HTTP 501，并明确提示该服务需要升级许可；因此 `aws_autoscaling_group` 的创建、实际容量和漂移测试**仅完成静态验证**，不能声称在 LocalStack 成功。其余资源均已实际 apply/destroy。

## 题目目标

将 ASG/launch template 与 IAM 用户拆成两个子模块，通过共享 AWS profile 分别 AssumeRole；`aws_caller_identity` 则使用 ro-user AssumeRole。先单独生成账号文件，再部署云资源，最后用 lifecycle 忽略 `desired_capacity` 变化。

## 开始前检查

启动独立 LocalStack；如果 4566 已占用，可改用 4567：

```powershell
docker run -d --name challenge3-localstack -p 4567:4566 `
  -e SERVICES=iam,sts,ec2,autoscaling localstack/localstack:4.14.0
docker ps --filter 'name=challenge3-localstack'
Invoke-RestMethod http://localhost:4567/_localstack/health
```

LocalStack 实验配置必须放在隔离副本。正式 AWS 配置不能包含 endpoint、`test` 凭证或跳过校验参数。

## Base Task：部署基础 IAM 资源

先进入 `challenge-3/base-folder`。正式 AWS 直接执行：

```powershell
terraform init
terraform validate
terraform apply -auto-approve
terraform output
```

预期创建 14 个资源，并输出 `EC2FullAccess`、`IAMFullAccess`、`ReadOnlyRole` 三个 ARN。LocalStack 实验需将 base-folder 的默认 provider 临时指向 4567：

```hcl
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    iam = "http://localhost:4567"
    sts = "http://localhost:4567"
  }
}
```

后续要写共享 credentials，但 access-key secret 只在创建时可取。可在 base-folder 临时增加敏感 outputs：

```hcl
output "kplabs_access_key_id" {
  value     = aws_iam_access_key.kplabs_user_key.id
  sensitive = true
}
output "kplabs_secret_access_key" {
  value     = aws_iam_access_key.kplabs_user_key.secret
  sensitive = true
}
output "ro_access_key_id" {
  value     = aws_iam_access_key.ro_user.id
  sensitive = true
}
output "ro_secret_access_key" {
  value     = aws_iam_access_key.ro_user.secret
  sensitive = true
}
```

执行一次 apply 保存 outputs。不要把 secret 输出到日志、聊天或 Git；写完 credentials 后可删除这些临时 output block。

## Task 1：拆分成子模块

在 `challenge-3` 下创建：

```text
modules/
├── asg/
│   └── main.tf   # aws_launch_template、aws_autoscaling_group
└── iam/
    └── main.tf   # aws_iam_user、aws_iam_user_policy
```

把对应 block 从 `challenge-3.tf` 原样移入模块。每个子模块都显式声明 AWS provider 来源，避免 `Reference to undefined provider` 警告：

```hcl
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
```

根模块添加调用；provider 映射会在 Task 3 完成：

```hcl
module "asg" {
  source = "./modules/asg"
  providers = {
    aws = aws.asg
  }
}

module "iam" {
  source = "./modules/iam"
  providers = {
    aws = aws.iam
  }
}
```

IAM policy 应引用同模块内的用户，避免创建顺序依赖字符串巧合：

```hcl
resource "aws_iam_user_policy" "lb_ro" {
  name = "ec2-describe-policy"
  user = aws_iam_user.lb[0].name
  # 原 policy 保持不变
}
```

```powershell
terraform fmt -recursive
terraform init
```

根目录资源此时尚未部署，不需要 `state mv`；base-folder 有自己的独立 state，不能移动到这里。

难点入口：搜索 `Terraform module provider mapping`；官网：[Providers within modules](https://developer.hashicorp.com/terraform/language/modules/develop/providers)。

## Task 2：创建共享 config 和 credentials

在 `challenge-3/.aws` 创建 `conf` 和 `credentials`。先读取角色 ARN：

```powershell
Set-Location base-folder
terraform output -raw ec2_fullaccess_role
terraform output -raw iam_fullaccess_role
terraform output -raw read_only_role_arn
Set-Location ..
```

`.aws/conf` 只能有 `asg` 和 `iam` 两个 profile。AWS config 文件的标准标题必须写成 `[profile NAME]`：

```ini
[profile asg]
role_arn = <EC2_FULL_ACCESS_ROLE_ARN>
source_profile = kplabs
region = us-east-1

[profile iam]
role_arn = <IAM_FULL_ACCESS_ROLE_ARN>
source_profile = kplabs
region = us-east-1
```

`.aws/credentials` 保存源用户凭证。`kplabs` 是两个 role profile 的 `source_profile`；`ro` 供只读 provider 使用：

```ini
[kplabs]
aws_access_key_id = <KPLABS_ACCESS_KEY_ID>
aws_secret_access_key = <KPLABS_SECRET_ACCESS_KEY>

[ro]
aws_access_key_id = <RO_ACCESS_KEY_ID>
aws_secret_access_key = <RO_SECRET_ACCESS_KEY>
```

将 `.aws/credentials` 加入 `.gitignore`，不要提交真实密钥：

```gitignore
challenge-3/.aws/credentials
```

PowerShell 可避免在控制台显示 secret，直接通过 AWS CLI 写文件：

```powershell
$env:AWS_CONFIG_FILE = (Resolve-Path '.aws').Path + '\conf'
$env:AWS_SHARED_CREDENTIALS_FILE = (Resolve-Path '.aws').Path + '\credentials'

$kId     = terraform -chdir=base-folder output -raw kplabs_access_key_id
$kSecret = terraform -chdir=base-folder output -raw kplabs_secret_access_key
$rId     = terraform -chdir=base-folder output -raw ro_access_key_id
$rSecret = terraform -chdir=base-folder output -raw ro_secret_access_key

aws configure set aws_access_key_id $kId --profile kplabs
aws configure set aws_secret_access_key $kSecret --profile kplabs
aws configure set aws_access_key_id $rId --profile ro
aws configure set aws_secret_access_key $rSecret --profile ro
```

角色 ARN、source profile 和 region 可按同样方式写入，或按上面的 INI 内容手动填写。

## Task 3：配置不同 Provider

根 `challenge-3.tf` 声明三个 aliased provider。正式 AWS 配置如下：

```hcl
provider "aws" {
  alias                    = "asg"
  region                   = "us-east-1"
  profile                  = "asg"
  shared_config_files      = ["${path.module}/.aws/conf"]
  shared_credentials_files = ["${path.module}/.aws/credentials"]
}

provider "aws" {
  alias                    = "iam"
  region                   = "us-east-1"
  profile                  = "iam"
  shared_config_files      = ["${path.module}/.aws/conf"]
  shared_credentials_files = ["${path.module}/.aws/credentials"]
}

provider "aws" {
  alias                    = "readonly"
  region                   = "us-east-1"
  profile                  = "ro"
  shared_credentials_files = ["${path.module}/.aws/credentials"]

  assume_role {
    role_arn = "<READ_ONLY_ROLE_ARN>"
  }
}
```

模块使用 Task 1 的 providers 映射；caller identity 显式使用只读 provider：

```hcl
data "aws_caller_identity" "local" {
  provider = aws.readonly
}
```

LocalStack 实验时，每个 provider 再添加对应的 `endpoints` 和三个 `skip_*` 参数。例如 ASG provider：

```hcl
skip_credentials_validation = true
skip_metadata_api_check     = true
skip_requesting_account_id  = true

endpoints {
  ec2         = "http://localhost:4567"
  autoscaling = "http://localhost:4567"
  sts         = "http://localhost:4567"
}
```

IAM provider 配 `iam`、`sts` endpoint；readonly provider 配 `sts` endpoint。

如需验明身份，可临时增加三个 `aws_caller_identity` data source。预期 ARN 分别包含：

```text
assumed-role/EC2FullAccess/
assumed-role/IAMFullAccess/
assumed-role/ReadOnlyRole/
```

```powershell
terraform fmt -recursive
terraform init -reconfigure
terraform validate
```

难点入口：搜索 `Terraform AWS provider profile assume_role alias`；官网：[Provider configuration](https://developer.hashicorp.com/terraform/language/providers/configuration)、[AWS Provider authentication](https://registry.terraform.io/providers/hashicorp/aws/5.80.0/docs#authentication-and-configuration)。

## Task 4：先创建账号文件，再部署资源

题目要求第一次 apply 只创建 `local_file.this`。Terraform 没有通用的“只部署某类资源”开关，因此先检查定向计划，再应用保存的 plan：

```powershell
terraform plan '-target=local_file.this' '-out=local-file.tfplan'
terraform show local-file.tfplan
terraform apply local-file.tfplan
terraform state list
Get-Content account-number.txt
```

预期 plan 为 `1 to add`，state 只有 caller data 与 `local_file.this`，文本内容为当前账号 ID。`-target` 会出现“Resource targeting is in effect”警告，这是本题明确要求分阶段部署造成的；不要把 target 用于日常 apply。

再部署其余资源：

```powershell
terraform plan '-out=all-resources.tfplan'
terraform apply all-resources.tfplan
terraform state list
```

真实 AWS 预期新增 launch template、ASG、`success-user` 和内联策略。LocalStack Community 实测新增了 launch template、IAM 用户及策略，但 ASG 返回 HTTP 501；这是未覆盖的许可差异，不是 Terraform provider 映射错误。

## Task 5：忽略 desired capacity 变化

必须先在 Task 4 以 `desired_capacity = 1` 成功创建 ASG，再修改为 2 并同时加入 lifecycle：

```hcl
resource "aws_autoscaling_group" "dev" {
  desired_capacity = 2
  max_size         = 2
  min_size         = 1

  # 其余原配置保持不变

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
```

如果在首次创建 ASG 前就把值改成 2，`ignore_changes` 不会忽略创建参数，初始容量仍会是 2；这不符合题目“保留原有容量 1”的目标。

验证：

```powershell
terraform fmt -recursive
terraform validate
terraform plan
```

在真实 AWS 中，预期 plan 不更新 ASG，实际 desired capacity 仍为 1：

```powershell
aws autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names '<ASG_NAME>' `
  --query 'AutoScalingGroups[0].DesiredCapacity'
```

返回应为 `1`。可以再次将 Terraform 中 `desired_capacity` 改成允许范围内的其他值并运行 plan，仍不应出现容量更新；测试后恢复题目要求的 2。注意：`ignore_changes` 同样会忽略控制台或 CLI 造成的容量漂移，Terraform 不会自动把它恢复为 1。

LocalStack Community 中本步骤仅完成 `terraform validate` 和静态 plan；因 ASG 无法创建，不能实际验证远端容量保持为 1。

难点入口：搜索 `Terraform lifecycle ignore_changes desired_capacity`；官网：[lifecycle ignore_changes](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#ignore_changes)。

## Destroy：销毁全部基础设施

先销毁根目录资源，再销毁提供凭证和角色的 base-folder。顺序不能反，否则根配置将失去 AssumeRole 所需凭证：

```powershell
terraform plan -destroy
terraform destroy -auto-approve
terraform state list

terraform -chdir=base-folder plan -destroy
terraform -chdir=base-folder destroy -auto-approve
terraform -chdir=base-folder state list
```

两份 state 最终都应为空。确认销毁后删除本地敏感文件：

```powershell
Remove-Item -LiteralPath .aws\credentials
Remove-Item -LiteralPath account-number.txt -ErrorAction SilentlyContinue
```

真实 AWS 再检查 ASG、launch template、`success-user`、三个角色和两个基础用户均不存在；不要删除同账号内无关资源。

## 最终检查

- base-folder 的 14 个资源先创建，角色 ARN和两组用户凭证可用。
- `.aws/conf` 只有 `asg`、`iam` 两个 role profile，region 都是 `us-east-1`。
- `.aws/credentials` 未提交 Git，asg/iam 共用 kplabs 用户，readonly 使用 ro-user。
- ASG、IAM 模块分别映射到 `aws.asg`、`aws.iam`。
- caller identity 通过 `aws.readonly` AssumeRole，账号文件先于其他资源创建。
- ASG 首次以容量 1 创建后，代码改为 2 且 plan 不更新实际容量。
- 先销毁根资源，再销毁 base-folder；两份 state 均为空。
