# Challenge 59：S3 Remote State 制品合同到 EC2 Launch Template 的版本传播

难度：**95 / 100**；考纲契合度：**A**。建议考试用时 **80 分钟**，完整学习与复盘 **150 分钟**。

本题包含两个独立 Terraform root。`publisher` 把两个发布制品写入 S3，并通过一份版本化、带指纹的 output contract 描述它们；`consumer` 只能通过真实 S3 `terraform_remote_state` 读取该合同，再把同一份 canonical release payload 同步到两份 Launch Template 审计规格与两台直接管理的 EC2 runtime。

```text
publisher state ──artifact_contract──▶ consumer
       │                                  ├── canonical payload ──▶ LT audit specs
       └── S3 artifact objects            └── canonical payload ──▶ EC2 runtimes
```

## 任务

只修改 `starter/publisher` 与 `starter/consumer`：

1. 两个 root 都声明空的 partial S3 backend。grader 会分别注入 `publisher/terraform.tfstate` 与 `consumer/terraform.tfstate`，候选代码不得硬编码 state bucket。
2. Publisher 严格验证制品 catalog 的顶层字段、schema、revision、精确两条制品、允许字段、安全 object key、owner、非空内容、重复 name 和重复 key。
3. Publisher 以制品 name 作为稳定 `for_each` key，只创建一个 `aws_s3_bucket` 和两个 `aws_s3_object`。数组及对象字段重排必须是严格 no-op；v1 → v2 只能原地更新两个对象。
4. `artifact_contract` 必须发布 contract version、producer run id、revision、bucket name/ARN、两条制品的 key/ARN/owner/SHA-256，以及基于 canonical `jsonencode` 的合同指纹。
5. Consumer 使用 S3 `terraform_remote_state`；配置必须包含字面量 `test/test`、path style、三项 skip flag 与 loopback S3 endpoint。不得读取 publisher 文件、枚举 S3 或复制合同常量来绕过远程状态。
6. Consumer 独立校验合同的精确字段、版本、run id、revision、bucket、制品 map、ARN、digest、owner 与指纹，同时严格校验 deployment manifest。两条节点必须以 `api`、`worker` 为稳定 key，重排不得改变地址。
7. 网络和 AMI 由 grader 通过 AWS CLI 创建；候选只允许 `data.aws_subnet` 与 `data.aws_ami` 精确读取，不得创建或发现 VPC、枚举子网，亦不得创建 AMI。
8. Consumer 创建一个 security group、两份 Launch Template 审计规格和两台 EC2。先生成每节点唯一的 canonical JSON payload；Launch Template 将它编码为 user data，EC2 则把同一原文作为实际 user data，并用直接的 AMI、subnet 与 security group 字段运行。这里不声明 EC2 与 Launch Template 的实际 association。
9. v1 → v2 时，两份 Launch Template 审计规格只能原地更新；两台实例必须同时通过 `user_data_replace_on_change`、`replace_triggered_by` 和 `create_before_destroy` 精确执行先建后删替换。仍声明期望 v1 的 consumer 必须拒绝 stale contract。
10. 最后按 consumer → publisher 生成、审计并应用 saved destroy plans，再清理 grader 创建的 state、VPC、subnet 与 AMI。

## 精确验收合同

- 固定使用 Terraform **1.6.6**，运行 publisher **10** 个、consumer **10** 个普通 `terraform test` runs；禁止 mock 和 override。负例独立覆盖顶层/record shape、revision/key/owner/content 语义、重复 identity、manifest shape 与 instance type。
- 初始 saved plans 必须精确为 publisher 3 个 create、consumer 5 个 create；state bucket 中必须恰好出现两条约定 key。
- grader 会下载真实 publisher state，分别删除一个合同字段和伪造 fingerprint，覆盖回同一 S3 key；consumer 必须由专属 schema/integrity 守卫拒绝，随后按原字节恢复 state。
- Publisher 与 consumer 的重排输入均严格 no-op。
- 手工覆盖 API S3 object 时，repair plan 只能更新该对象；手工修改 API EC2 `Name` tag 时，repair plan 只能更新该实例。
- Publisher v2 plan 只能更新两条 object；consumer v2 plan 必须精确更新两份 Launch Template，并以 `create,delete` 替换两台 EC2。grader 会通过 EC2 API 回读 v1/v2 实例的实际 UserData，验证 ARN、digest、revision、node 与 source state。
- 两个 root 最终 clean；consumer 5 项、publisher 3 项 saved destroy 精确匹配；S3、EC2、Launch Template、security group、remote state、VPC、subnet 与 AMI 均零残留。

## 边界

Terraform 版本约束为 `~> 1.6`，AWS provider 为 `~> 5.100`。所有 AWS provider 和 remote-state 凭证均为字面量 `test/test`，endpoint 必须是带显式端口的 loopback LocalStack root origin。

禁止 SNS、ASG、候选 VPC 资源或发现、`terraform_data`、mock/override、provisioner、候选脚本、`ignore_changes`，以及任何真实 AWS endpoint。由于 LocalStack Community 对实例 Launch Template association 的回读不稳定，本题明确使用直接 EC2 字段加共享 canonical payload；不得把审计规格虚构为真实 association。LocalStack Community 环境中不依赖收费服务。

```powershell
$env:PATH = "$env:TEMP\tfpro-terraform-1.6.6;$env:PATH"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```
