# Challenge 55：Security Group Rule 模型与 ASG Schema 的 LocalStack 边界

官方 AWS 学习清单同时列出 legacy `aws_security_group_rule`、现代
`aws_vpc_security_group_ingress_rule` 和 `aws_autoscaling_group`。LocalStack Community
可以运行前两类网络对象和 Launch Template，却不提供可用的 Auto Scaling API。本题会真实
部署安全组/LT，用 `count = 0` 练 ASG schema，并用 `terraform_data` 明确替代容量运行期；
不会把替代物冒充真实 ASG。

## 官方考试目标

- **2d**：Use meta-arguments in configuration
- **5a**：Understand Terraform's plugin-based architecture

AWS 资源范围来自 [Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-55
terraform init
terraform plan '-out=c55-baseline.tfplan'
terraform apply .\c55-baseline.tfplan
terraform output starter_contract
~~~

Starter 查询默认 AMI/Subnet，创建一个 security group、一条 legacy SSH rule、一个 launch
template 和容量 surrogate。LocalStack 不会启动虚拟机。

## Task 1：先辨认两种 Rule 的 State 模型

~~~powershell
terraform state show aws_security_group_rule.legacy_ssh
$contract = terraform output -json starter_contract | ConvertFrom-Json
$sgId = $contract.security_group_id
aws --endpoint-url=http://localhost:4566 ec2 describe-security-group-rules --filters "Name=group-id,Values=$sgId"
~~~

记录 legacy resource 在 state 中如何同时承载 protocol、ports、CIDRs；API 返回的 rule ID
则代表远端独立规则。不要在 `aws_security_group.fleet` 中再写 inline ingress。

## Task 2：只练习 ASG Schema，不调用不支持的 API

先检查 provider schema：

~~~powershell
terraform providers schema -json |
  Set-Content -Encoding utf8 .\c55-schema.json
$schema = Get-Content -Raw .\c55-schema.json | ConvertFrom-Json
$schema.provider_schemas.'registry.terraform.io/hashicorp/aws'.resource_schemas.aws_autoscaling_group.block
~~~

随后添加 `aws_autoscaling_group.schema_drill`，要求：

- `count = 0`，确保 plan 不调用 Community 版缺失的 ASG API；
- min 1、max 4、desired 来自变量；
- 使用查询到的 subnet 与现有 launch template；
- lifecycle 忽略 `desired_capacity`，表达外部 autoscaler 可管理该字段。

~~~powershell
terraform fmt
terraform validate
terraform plan
~~~

计划应为 `No changes`，但 provider schema 会完整验证 block。不得把 `count` 改成 1，也不得
声称已完成真实 ASG apply。

## Task 3：并列创建一条现代独立 Rule

添加 `aws_vpc_security_group_ingress_rule.https`，绑定同一个 security group：

- TCP 443–443；
- CIDR `10.55.0.0/16`；
- 描述 `modern-resource-model`。

~~~powershell
terraform plan '-out=c55-https.tfplan'
terraform apply .\c55-https.tfplan
terraform state list
~~~

预期只新增现代 rule。Legacy SSH 与现代 HTTPS 的语义不重叠，因此不会互相争抢同一远端规则。

## Task 4：把现代 Rules 扩展成稳定业务键

建立一个 HCL map catalog，包含 `http` 80 与 `https` 443。把现代 resource 改为
`for_each`，key 使用业务名；添加一条 `moved` 将原 `https` 地址迁到
`["https"]`。

~~~powershell
terraform plan '-out=c55-rules.tfplan'
terraform show c55-rules.tfplan
terraform apply c55-rules.tfplan
terraform plan
~~~

计划应把 HTTPS 视为地址 move/no-op，只新增 HTTP。重排 map 源码后仍须 `No changes`。
Legacy SSH 保持原地址，不在同一次任务中顺便迁移资源类型。

## Task 5：观察 Desired Capacity 的所有权

先把 `desired_capacity` 从 1 改成 2：

~~~powershell
terraform plan
~~~

`count = 0` 的 ASG 不产生动作，但 `terraform_data.desired_capacity` 会提出 in-place update。
现在给 surrogate 的 `input` 添加 `ignore_changes`，再次 plan；它应无变更，state 仍保留 1。
解释这与 ASG 忽略 desired capacity 的共同生命周期概念，以及 surrogate 不具备的真实扩缩容能力。

## Task 6：State/API 双向验收并清理

~~~powershell
terraform state list
terraform output starter_contract
aws --endpoint-url=http://localhost:4566 ec2 describe-launch-templates --launch-template-ids $(terraform output -json starter_contract | ConvertFrom-Json | Select-Object -ExpandProperty launch_template_id)
terraform destroy -auto-approve
~~~

销毁后 API 不应再找到本题 LT/SG/rules。删除 schema、plans、`.terraform`、lockfile/state，
恢复 `challenge-55.tf` starter，最终只保留两份源文件。

## LocalStack Community 边界

- `count = 0` 只覆盖 HCL/provider schema 与 meta-argument，不覆盖 ASG API 行为。
- 容量 surrogate 只保留 lifecycle ownership 练习，不能创建、扩缩或健康检查 EC2。
- 考试若提供真实 AWS ASG，应使用真实资源；不要把本题替代方式当成生产答案。
