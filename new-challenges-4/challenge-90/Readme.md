# Challenge 90：IAM → Instance Profile → Launch Template → EC2 依赖闭包

Starter 已声明一条完整交付链：IAM role、managed policy、attachment、instance profile、
launch template 和 EC2 instance。所有 HCL 都可解析，但当前依赖图缺少一条业务边：
Launch Template 引用了 instance profile，却没有证明独立的 policy attachment 已经完成。
你要通过 targeted plan 的依赖闭包发现缺口，只添加一个最小 `depends_on`，再完成部署。

## 学习目标

- 从表达式与 targeted plan 识别隐式依赖闭包中缺失的业务边；
- 把唯一显式 `depends_on` 放在最小、可复用的依赖位置；
- 在一次受控 target apply 后回到完整 plan，并从 IAM、Launch Template、EC2 API 验收。

## 考纲定位

- **2d**：Use meta-arguments and reason about dependency graphs
- **1b / 1c**：Generate/review targeted plans and return to the full workflow
- **2b / 5b**：AWS data sources、Provider resources 与依赖路由

Target 在本题只用于观察和一次受控分阶段部署，不是日常发布模式。

## 开始前

```powershell
Set-Location .\new-challenges-4\challenge-90
terraform version
Invoke-RestMethod http://localhost:4566/_localstack/health
$env:AWS_ACCESS_KEY_ID = 'test'
$env:AWS_SECRET_ACCESS_KEY = 'test'
$env:AWS_DEFAULT_REGION = 'us-east-1'
```

Terraform 必须是 1.6.x，LocalStack 的 IAM、EC2、STS 服务必须可用。Starter 没有 state；
Task 1 前不要 apply。

## 任务

### Task 1：比较完整计划与缺边的 Target 闭包

工作目录：`new-challenges-4/challenge-90`

```powershell
terraform init
terraform fmt -check
terraform validate
terraform graph
terraform plan
terraform plan '-target=aws_instance.workload' '-out=before-edge.tfplan'
terraform show before-edge.tfplan
```

完整 plan 有 6 个 managed resources 待创建。缺边的 targeted plan 通常只包含 4 个：
role、instance profile、launch template、instance；policy 与 attachment 不在 instance 的
上游闭包中。不要 apply `before-edge.tfplan`。

### Task 2：逐条区分隐式边与缺失业务边

阅读表达式并核对图：

- instance profile 引用 role，已有隐式边；
- attachment 引用 role 与 policy，已有两条隐式边；
- launch template 引用 instance profile，已有隐式边；
- instance 引用 launch template 的 image、instance type 与 ID，已有隐式边；
- 没有任何值引用把 policy attachment 放到 launch template 的上游。

可以用下面的只读命令缩小图文本：

```powershell
terraform graph | Select-String -Pattern 'aws_iam_role_policy_attachment|aws_iam_instance_profile|aws_launch_template|aws_instance'
```

不要给每个资源都加 `depends_on`，也不要重复已有引用建立的边。

### Task 3：只添加一条最小显式依赖

在 `aws_launch_template.workload` 中添加：

```hcl
depends_on = [aws_iam_role_policy_attachment.workload]
```

放在 launch template 而不是 instance 上，是因为任何使用该 template 的计算资源都应该在
权限 attachment 就绪后启动。Instance profile 的引用继续负责另一条隐式边。

```powershell
terraform fmt
terraform validate
terraform graph
```

### Task 4：重新审阅完整 Target 闭包并应用

```powershell
terraform plan '-target=aws_instance.workload' '-out=complete-closure.tfplan'
terraform show complete-closure.tfplan
```

现在 saved plan 必须包含 6 个 managed resources：role、policy、attachment、instance
profile、launch template、instance。确认没有无关对象后才执行：

```powershell
terraform apply complete-closure.tfplan
terraform state list
```

Target 警告是预期的；下一步必须立即回到完整 plan。

### Task 5：同时验证 IAM、Launch Template 与 EC2 API

```powershell
terraform plan -detailed-exitcode
$LASTEXITCODE
terraform output -json delivery_contract
aws --endpoint-url=http://localhost:4566 iam list-attached-role-policies `
  --role-name TfProChallenge90Workload
aws --endpoint-url=http://localhost:4566 iam get-instance-profile `
  --instance-profile-name TfProChallenge90Workload
```

完整 plan 退出码必须是 `0`。取得 output 中的 IDs 后继续核验：

```powershell
$contract = terraform output -json delivery_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 ec2 describe-launch-template-versions `
  --launch-template-id $contract.launch_template `
  --versions '$Latest' `
  --query 'LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile.Name'
aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
  --instance-ids $contract.instance_id `
  --query 'Reservations[0].Instances[0].[InstanceId,ImageId,InstanceType,IamInstanceProfile.Arn,Tags[?Key==`LaunchTemplateId`].Value|[0]]'
```

IAM policy 已附着到正确 role；profile 包含该 role；launch template 指向正确 profile；
instance 的 AMI、规格和 profile 与 template 契约一致，`LaunchTemplateId` 审计标签也等于
output 中的 template ID。

### Task 6：验收最小依赖并清理

最终配置只能有这一条新增的显式 `depends_on`。再次运行：

```powershell
terraform fmt -check
terraform validate
terraform plan -detailed-exitcode
$LASTEXITCODE
```

退出码必须为 `0`。然后清理：

```powershell
terraform destroy -auto-approve
terraform state list
Remove-Item .\before-edge.tfplan,.\complete-closure.tfplan `
  -Force -ErrorAction SilentlyContinue
```

Destroy 图应按 instance → launch template → attachment/profile → role/policy 的安全反向顺序
完成。

## Terraform 1.6 与 LocalStack 边界

- 本题只使用 Terraform 1.6 的静态 `depends_on`、resource targeting 和 saved plan。
- LocalStack Community 可运行 IAM、instance profile、launch template 与 EC2；不依赖付费的
  Auto Scaling API。
- 当前 LocalStack Community 不能稳定回读 `aws_instance.launch_template` 元数据，因此 starter
  让 instance 直接引用 launch template 的 `image_id`、`instance_type` 和 ID 标签来保留真实
  Terraform 图边，同时用真实 instance profile 完成权限链。这个取舍避免实验结束后出现虚假的
  replacement plan，不改变本题对依赖闭包的训练目标。
- 不使用 `-target` 逐个补资源、sleep/provisioner、脚本、手工 state 或新版
  `action_trigger`。
