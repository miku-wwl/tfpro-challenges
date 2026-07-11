# Challenge 6 解题教程

## 验证说明

本教程使用 Terraform v1.14.0、根 AWS Provider v5.80.0、base-folder AWS Provider v5.82.2、Local Provider v2.9.0、Docker 29.4.3 和 LocalStack Community v4.14.0 完整实测。

Base Task 实际创建 19 个资源；根配置实际创建 `demo-firewall`、`CloudWatchFullAccess` role 和独立 policy attachment。三个 caller ARN分别包含 `assumed-role/IAMFullAccess/`、`assumed-role/EC2FullAccess/`、`assumed-role/ReadOnlyRole/`，证明三个身份链有效。最后先销毁根目录 3 个资源，再销毁 base-folder 19 个资源，两份 state 均为空。

## 题目目标

构建三个 AWS role profile，但 credentials 文件只保存 IAM/EC2 两组源凭证；readonly profile 从 base-folder 的 default 凭证开始 AssumeRole。Terraform 中让 IAM role、安全组和 caller identity 分别使用对应 provider，并消除 `managed_policy_arns` 弃用警告。

## 开始前检查

启动独立 LocalStack；若 4566 已占用可改绑 4567：

```powershell
docker run -d --name challenge6-localstack -p 4567:4566 `
  -e SERVICES=iam,ec2,sts localstack/localstack:4.14.0
Invoke-RestMethod http://localhost:4567/_localstack/health
```

LocalStack 专用 endpoint、测试凭证和 `skip_*` 只能放在实验副本，正式 AWS 配置不得保留。

## Base Task：部署身份资源

```powershell
Set-Location challenge-6\base-folder
terraform init
terraform validate
terraform apply -auto-approve
terraform output
Get-Content default-creds.txt
```

预期创建 19 个资源，输出三个 role ARN，并生成只含 `[default]` 的 `default-creds.txt`。该文件和后续 `.aws/credentials` 都包含 secret，禁止提交 Git或复制到日志。

为了取得另外两组只在创建时可读的 secret，可临时在 base-folder 增加敏感 outputs：

```hcl
output "iam_access_key_id" {
  value     = aws_iam_access_key.iam_user_key.id
  sensitive = true
}
output "iam_secret_access_key" {
  value     = aws_iam_access_key.iam_user_key.secret
  sensitive = true
}
output "ec2_access_key_id" {
  value     = aws_iam_access_key.ec2_user.id
  sensitive = true
}
output "ec2_secret_access_key" {
  value     = aws_iam_access_key.ec2_user.secret
  sensitive = true
}
```

写完 credentials 后可删除临时 outputs。LocalStack 实验中把 base provider 临时指向 `iam`、`sts` 的 4567 endpoint。

## Task 1：创建 AWS config

在 `challenge-6/.aws/config` 中只写以下三个 profile：

```ini
[profile readonly-access]
region = us-east-1
output = text
role_arn = <READ_ONLY_ROLE_ARN>
source_profile = default

[profile iam-access]
region = us-east-1
output = text
role_arn = <IAM_FULL_ACCESS_ROLE_ARN>
source_profile = iam-access

[profile ec2-access]
region = us-east-1
output = text
role_arn = <EC2_FULL_ACCESS_ROLE_ARN>
source_profile = ec2-access
```

三个 ARN 从 base-folder 查询：

```powershell
terraform -chdir=base-folder output -raw read_only_role_arn
terraform -chdir=base-folder output -raw iam_fullaccess_role
terraform -chdir=base-folder output -raw ec2_fullaccess_role
```

AWS config 文件的 profile 标题必须使用 `[profile NAME]`；`[default]` 不允许出现在本目录文件中。

## Task 2：创建 credentials

`challenge-6/.aws/credentials` 必须恰好只有两节：

```ini
[iam-access]
aws_access_key_id = <KPLABS_IAM_USER_ACCESS_KEY>
aws_secret_access_key = <KPLABS_IAM_USER_SECRET_KEY>

[ec2-access]
aws_access_key_id = <KPLABS_EC2_USER_ACCESS_KEY>
aws_secret_access_key = <KPLABS_EC2_USER_SECRET_KEY>
```

不要增加 readonly/default。可以避免在控制台显示 secret，直接写入指定文件：

```powershell
$env:AWS_CONFIG_FILE = (Resolve-Path '.aws\config').Path
$env:AWS_SHARED_CREDENTIALS_FILE = (Resolve-Path '.aws').Path + '\credentials'
$iamId     = terraform -chdir=base-folder output -raw iam_access_key_id
$iamSecret = terraform -chdir=base-folder output -raw iam_secret_access_key
$ec2Id     = terraform -chdir=base-folder output -raw ec2_access_key_id
$ec2Secret = terraform -chdir=base-folder output -raw ec2_secret_access_key
aws configure set aws_access_key_id $iamId --profile iam-access
aws configure set aws_secret_access_key $iamSecret --profile iam-access
aws configure set aws_access_key_id $ec2Id --profile ec2-access
aws configure set aws_secret_access_key $ec2Secret --profile ec2-access
```

确保 `.aws/credentials` 已被 `.gitignore` 排除。

## Task 3：配置 readonly 的 source profile

Task 1 中 `source_profile = default` 已建立关系。default 凭证不在 challenge-6 的 `.aws` 文件中，而在：

```text
base-folder/default-creds.txt
```

因此不要把 `[default]` 复制到 `.aws/config` 或 `.aws/credentials`。Terraform provider 可直接读取这个外部 credentials 文件，再按 config 中的 ReadOnlyRole ARN执行 AssumeRole。

## Task 4：修改多 Provider 配置

在 `challenge-6.tf` 配置三个 alias。IAM/EC2 使用本地 profile：

```hcl
provider "aws" {
  alias                    = "iam"
  region                   = "us-east-1"
  profile                  = "iam-access"
  shared_config_files      = ["${path.module}/.aws/config"]
  shared_credentials_files = ["${path.module}/.aws/credentials"]
}

provider "aws" {
  alias                    = "ec2"
  region                   = "us-east-1"
  profile                  = "ec2-access"
  shared_config_files      = ["${path.module}/.aws/config"]
  shared_credentials_files = ["${path.module}/.aws/credentials"]
}
```

Readonly provider 直接使用 base-folder 的 default 凭证及 ReadOnlyRole：

```hcl
provider "aws" {
  alias                    = "readonly"
  region                   = "us-east-1"
  profile                  = "default"
  shared_credentials_files = ["${path.module}/base-folder/default-creds.txt"]

  assume_role {
    role_arn = "<READ_ONLY_ROLE_ARN>"
  }
}
```

然后给每个对象指定 provider：

```hcl
resource "aws_security_group" "allow_tls" {
  provider = aws.ec2
  name     = "demo-firewall"
}

data "aws_caller_identity" "current" {
  provider = aws.readonly
}

resource "aws_iam_role" "cw_full_access" {
  provider = aws.iam
  name     = "CloudWatchFullAccess"
  # assume_role_policy 保持原逻辑
}
```

LocalStack 中三个 provider 分别添加对应 endpoint：IAM=`iam,sts`，EC2=`ec2,sts`，readonly=`sts`，并添加测试环境所需 `skip_*`。

验证身份时可临时添加 caller data source：

```hcl
data "aws_caller_identity" "iam_verify" { provider = aws.iam }
data "aws_caller_identity" "ec2_verify" { provider = aws.ec2 }
```

`terraform state show` 中三个 ARN必须分别包含 `IAMFullAccess`、`EC2FullAccess`、`ReadOnlyRole`。验证后删除临时 data/output，避免每次 AssumeRole session 名变化导致 output diff。

难点入口：搜索 `Terraform AWS provider shared config profile assume role alias`；官网：[AWS Provider configuration](https://registry.terraform.io/providers/hashicorp/aws/5.80.0/docs)、[Provider configuration](https://developer.hashicorp.com/terraform/language/providers/configuration)。

## Task 5：创建资源

```powershell
terraform fmt
terraform init
terraform validate
terraform plan '-out=challenge6.tfplan'
terraform apply challenge6.tfplan
terraform state list
terraform output account_id
```

预期创建安全组、CloudWatch role 以及 Task 6 的独立 attachment，共 3 个资源；account ID正常输出。实测 profile 名同时出现在 config/credentials 中，并把自身写为 source profile，Terraform AWS Provider v5.80.0 能成功取得相应 assumed-role 身份。

## Task 6：删除弃用警告

原配置的 `managed_policy_arns` 已弃用。将其从 role 删除：

```hcl
resource "aws_iam_role" "cw_full_access" {
  provider = aws.iam
  name     = "CloudWatchFullAccess"

  assume_role_policy = jsonencode({
    # 保持原策略内容
  })
}
```

改用独立 attachment，并使用同一个 IAM provider：

```hcl
resource "aws_iam_role_policy_attachment" "cw_full_access" {
  provider   = aws.iam
  role       = aws_iam_role.cw_full_access.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}
```

```powershell
terraform fmt
terraform validate
terraform plan
```

最终不能再出现 `managed_policy_arns is deprecated`；资源已按最终配置创建时，plan 应为 `No changes`。

## Task 7：销毁

必须先销毁依赖三个角色和 access key 的根资源，再销毁 base-folder：

```powershell
terraform plan -destroy
terraform destroy -auto-approve
terraform state list

terraform -chdir=base-folder plan -destroy
terraform -chdir=base-folder destroy -auto-approve
terraform -chdir=base-folder state list
```

两份 state 都应为空，`default-creds.txt` 会随 local_file 一起删除。确认 `.aws/credentials` 不再需要后手动删除，避免遗留密钥。

## 最终检查

- `.aws/config` 只有 readonly/iam/ec2 三个 profile，均为 us-east-1、text。
- `.aws/credentials` 只有 IAM/EC2 两节，凭证用户匹配。
- readonly 的 `source_profile = default`，default 凭证只在 base-folder 文件中。
- IAM role、安全组、caller identity 分别使用正确 provider。
- 三个 caller ARN均为对应 assumed role。
- `managed_policy_arns` 已改为独立 attachment，无弃用警告。
- 根目录先 destroy，base-folder 后 destroy，两份 state 均为空。
