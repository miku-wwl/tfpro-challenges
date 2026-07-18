# Challenge 55：真实 ASG Runtime、Security Group Rule 模型与容量漂移

同一个 security group 可以由 legacy `aws_security_group_rule` 或现代
`aws_vpc_security_group_ingress_rule` 管理独立规则；Auto Scaling Group 则会根据 Launch
Template 和容量边界管理一组 EC2 instances。本题把两条线放进一个真实运行的 fleet：先比较
rule 的 state 模型，再扩容 ASG、制造远端容量漂移，并用 lifecycle 明确字段所有权。

本题要求支持 EC2 与 Auto Scaling API 的 **LocalStack Ultimate**。Starter 中的
`aws_autoscaling_group` 会通过 AWS provider 调用真实的 Auto Scaling API。

## 官方考试目标

- **1e**：Manage resource state, including reconciling resource drift
- **2b**：Query providers using data sources
- **2d**：Use meta-arguments in configuration

AWS 资源类型来自 [Terraform Professional Exam Content List](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)。
本题固定兼容 Terraform `>= 1.6.0, < 2.0.0` 与 AWS provider `5.80.0`。

## 开始前确认

先确认 LocalStack 正在 `http://localhost:4566` 提供服务，而且 Auto Scaling API 可用：

```powershell
Set-Location .\new-challenges-2\challenge-55
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"
$env:AWS_DEFAULT_REGION = "us-east-1"

aws --endpoint-url=http://localhost:4566 sts get-caller-identity
aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --max-items 1
```

若第二条命令提示服务不可用，应先检查 LocalStack Ultimate 的许可与服务状态；API 可用后再开始
baseline，不要在服务异常时继续 apply。

## Starter 状态

先只阅读 `challenge-55.tf`，确认依赖链：默认 subnet 与 AMI data sources 提供已有对象，
security group 被 Launch Template 引用，Launch Template 再被 ASG 引用。Starter 包含：

- legacy SSH rule：TCP 22，CIDR `10.55.0.0/16`；
- Launch Template：`t3.micro`，使用查询到的 AMI 与 security group；
- 真实 ASG `tfpro-c55-fleet`：min/desired/max 为 1/1/4；
- EC2 health check、300 秒 grace period 与 `2m` capacity waiter。

此时还没有现代 rule，也没有 lifecycle 忽略规则。

## Task 1：部署并证明 ASG 真实存在

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c55-baseline.tfplan'
terraform show .\c55-baseline.tfplan
terraform apply .\c55-baseline.tfplan
Remove-Item -LiteralPath .\c55-baseline.tfplan
```

计划应创建 security group、legacy rule、Launch Template 和 ASG 四个受 Terraform 管理的资源。
ASG 启动的 instance 属于 fleet，不会另外出现一个 `aws_instance` resource address。

现在同时从 state 与 API 验收：

```powershell
terraform state list
terraform state show aws_autoscaling_group.fleet
$contract = terraform output -json fleet_contract | ConvertFrom-Json

$asg = aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $contract.autoscaling_group | ConvertFrom-Json
$asg.AutoScalingGroups[0] |
  Select-Object AutoScalingGroupName,MinSize,DesiredCapacity,MaxSize,LaunchTemplate,Instances

$instanceIds = @($asg.AutoScalingGroups[0].Instances | ForEach-Object InstanceId)
if ($instanceIds.Count -gt 0) {
  aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
    --instance-ids $instanceIds `
    --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name,Image:ImageId,Type:InstanceType}'
}
```

API 中的 group name、容量、Launch Template ID 应与 `fleet_contract` 一致；至少一个 instance 应为
`Healthy/InService`。`2m` waiter 会让 apply 等到 starter 容量进入服务，而不是只检查 ASG 对象已创建。

## Task 2：并列比较 Legacy 与现代 Rule

先观察 legacy resource 与远端 rule ID：

```powershell
terraform state show aws_security_group_rule.legacy_ssh
aws --endpoint-url=http://localhost:4566 ec2 describe-security-group-rules `
  --filters "Name=group-id,Values=$($contract.security_group_id)"
```

在同一个 `.tf` 文件中添加 `aws_vpc_security_group_ingress_rule.https`：

- `security_group_id` 引用 `aws_security_group.fleet.id`；
- `ip_protocol = "tcp"`，from/to port 都是 `443`；
- `cidr_ipv4 = "10.55.0.0/16"`；
- description 为 `modern-resource-model`。

不要在 `aws_security_group.fleet` 内添加 inline ingress，也不要修改已有 SSH rule。

```powershell
terraform fmt
terraform validate
terraform plan '-out=c55-https.tfplan'
terraform show .\c55-https.tfplan
terraform apply .\c55-https.tfplan
Remove-Item -LiteralPath .\c55-https.tfplan
terraform state list
```

本步应只新增 HTTPS rule。比较两个 rule 的 state addresses 与属性形状，并解释为什么不同端口的
独立 resources 不会争抢同一条远端规则。

## Task 3：用稳定业务键扩展现代 Rules

建立一个 local map，包含 `http` 与 `https`：端口分别为 80 和 443，CIDR 都是
`10.55.0.0/16`。把现代 rule 改为 `for_each`，key 直接使用业务名；description 应能区分
`http-modern-resource-model` 与 `https-modern-resource-model`。

原来的 HTTPS 已在 state 中，必须同时添加 `moved` block，把：

```text
aws_vpc_security_group_ingress_rule.https
```

迁移到：

```text
aws_vpc_security_group_ingress_rule.modern["https"]
```

```powershell
terraform fmt
terraform validate
terraform plan '-out=c55-rules.tfplan'
terraform show .\c55-rules.tfplan
terraform apply .\c55-rules.tfplan
Remove-Item -LiteralPath .\c55-rules.tfplan
terraform plan
```

审阅计划时不要只看摘要：HTTPS 应显示 address move，并因 description 变化最多发生一次原地
更新；HTTP 应是唯一新增 rule。应用后普通 plan 应为 `No changes`。重排 map 的源码顺序也不应
改变实例地址。

## Task 4：让真实 ASG 从 1 扩到 2

把 `desired_capacity` 的 default 从 `1` 改为 `2`，暂时不要添加 lifecycle：

```powershell
terraform plan '-out=c55-scale.tfplan'
terraform show .\c55-scale.tfplan
terraform apply .\c55-scale.tfplan
Remove-Item -LiteralPath .\c55-scale.tfplan

$contract = terraform output -json fleet_contract | ConvertFrom-Json
aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $contract.autoscaling_group `
  --query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Instances:Instances[].InstanceId}'
```

Terraform 应原地更新真实 ASG，而不是替换 Launch Template、security group 或 ASG。API 的
desired 应为 2；实例列表可能需要短暂等待才收敛。这里的扩容由 Auto Scaling 服务完成，
Terraform state 只跟踪 ASG 对象。

## Task 5：制造漂移并划分 Desired Capacity 所有权

先模拟外部 autoscaler，把远端 desired capacity 改为 3：

```powershell
aws --endpoint-url=http://localhost:4566 autoscaling update-auto-scaling-group `
  --auto-scaling-group-name $contract.autoscaling_group `
  --desired-capacity 3

aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $contract.autoscaling_group `
  --query 'AutoScalingGroups[0].DesiredCapacity'
terraform plan
```

普通 plan 应发现 drift，并准备把 3 改回配置中的 2；先不要应用。随后只在
`aws_autoscaling_group.fleet` 添加：

```hcl
lifecycle {
  ignore_changes = [desired_capacity]
}
```

```powershell
terraform fmt
terraform validate
terraform plan
terraform apply -refresh-only -auto-approve
terraform plan
terraform state show aws_autoscaling_group.fleet
```

加入 lifecycle 后，第一个 plan 不应再包含 ASG 更新动作；它仍可能显示
`fleet_contract.desired_capacity` 从 2 刷新为 3，因为 `ignore_changes` 不会阻止 refresh 或 output
更新。`apply -refresh-only` 只把观察到的 3 写入 state，不会扩缩容；随后 plan 才应为
`No changes`，远端 desired 仍为 3。

`ignore_changes` 没有忽略 min/max、Launch Template 或整个 resource；它只把
`desired_capacity` 的更新所有权交给外部系统。解释为什么这与从配置中删除 ASG 或执行
`state rm` 完全不同。

## Task 6：State/API 双向验收并清理

先保存 ASG 当前管理的 instance IDs，完成最后一次一致性检查：

```powershell
$asg = aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $contract.autoscaling_group | ConvertFrom-Json
$instanceIds = @($asg.AutoScalingGroups[0].Instances | ForEach-Object InstanceId)

terraform state list
terraform output fleet_contract
terraform plan
terraform destroy -auto-approve
terraform state list
```

销毁后验证 ASG/LT/SG 已不存在；先前由 ASG 管理的 instances 应处于 `terminated`：

```powershell
aws --endpoint-url=http://localhost:4566 autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names $contract.autoscaling_group
aws --endpoint-url=http://localhost:4566 ec2 describe-launch-templates `
  --launch-template-ids $contract.launch_template_id
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups `
  --group-ids $contract.security_group_id

if ($instanceIds.Count -gt 0) {
  aws --endpoint-url=http://localhost:4566 ec2 describe-instances `
    --instance-ids $instanceIds `
    --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name}'
}
```

前 3 个 API 查询中，ASG 与 LT 应返回空列表，SG 应返回 not found；instance 的终止历史记录
可以继续存在。最后把 `challenge-55.tf` 恢复到 starter 内容，删除 `.terraform`、lockfile、
state 与所有 plan 运行产物，使目录重新只剩 `Readme.md` 和 `challenge-55.tf`。

## 边界与易错点

- 本题必须运行真实 `aws_autoscaling_group`，并同时用 state 与 API 验收。
- 不要混用 inline ingress 与独立 rule resources 管理同一条规则。
- 保留 `2m` capacity waiter；不要把它设为 `"0"` 来隐藏实例未进入服务的问题。
- 使用正常销毁流程，不要用 `force_delete = true` 绕过 ASG 缩容和实例终止。
- `ignore_changes` 只影响更新计划；Terraform destroy 仍会销毁 ASG。
- ASG 启动的 instances 不拥有独立 Terraform resource addresses，其生命周期由 ASG 管理。
