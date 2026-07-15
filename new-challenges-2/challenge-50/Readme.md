# Challenge 50：三 S3 State 合同链与双区域发布 Capstone

难度：**95 / 100**；考纲契合度：**A**。建议考试用时 **90 分钟**，完整学习与复盘 **170 分钟**。

本题维护三个独立 Terraform root 和三份真实 S3 state：

```text
identity ──identity_contract──▶ platform ──platform_contract──▶ workload
    └────────────────identity_contract────────────────────────▶ workload
```

`identity` 独占 IAM；`platform` 消费 identity 合同并发布 S3 release；`workload` 同时消费两份合同，再通过显式 provider alias 发布双区域 EC2。下游只能读取版本化 outputs，不能读取上游配置文件、复制常量或枚举云资源伪造合同。

## 任务

只修改 `starter/identity`、`starter/platform` 与 `starter/workload`：

1. 三个 root 都使用空的 partial S3 backend，state key 固定为 `identity/`、`platform/`、`workload/terraform.tfstate`；外部 state bucket/config 由 grader 注入。
2. Identity 只创建 IAM role、managed policy、role-policy attachment 与 instance profile。最小策略只允许读取本题 release object，并输出 contract version、run id、role/profile、policy ARN 与 canonical SHA-256。
3. Platform 通过 S3 `terraform_remote_state` 验证 identity contract；严格验证 manifest 字段、版本、安全 key、payload 路径与真实 `filesha256`；只创建一个 S3 bucket 和一个 object。
4. Platform output 必须包含稳定 artifact 地址/digest，并保存 `sha256(jsonencode(identity_contract))`，形成可验证的合同链。
5. Workload 通过两份独立 S3 `terraform_remote_state` 验证版本、run id、期望 release、bucket/artifact 和 identity fingerprint；同时严格验证两条 fleet 的 schema 与稳定 `name@location` identity。
6. Default 与 `aws.dr` 显式映射到 regional module。候选只允许 `data.aws_subnet`；网络与 AMI 由 grader 注入，候选不得创建/发现 VPC 或查询 AMI。
7. 两区各创建一台 `aws_instance`，user data 和 tags 携带 release、artifact ARN/digest 与 fleet trace。使用官方 `user_data_replace_on_change = true` 让平台 v2 合同精确替换两台实例。
8. 严格按 workload → platform → identity 使用 saved destroy，最后清理三份 state 与 grader 临时依赖。

## 精确验收合同

- Canonical suite：identity **4**、platform **7**、workload **8** 个普通 Terraform 1.6.6 runs，无 mock/override。
- 初始 saved plans：identity 4 个 create、platform 2 个 create、workload 2 个 create；S3 中必须恰好出现三条 state key。
- Fleet catalog 重排严格 no-op；手工修改 S3 object 或 EC2 Name tag 时，只允许对应单资源 update。
- Platform v1 → v2 只更新 object；仍期望 v1 的 workload 必须失败；改为期望 v2 后只替换两台 EC2。
- 三个 root 最终都 clean；三个 saved destroy 按逆依赖顺序执行；IAM、S3、EC2 和外部 state/network/AMI 均零残留。

## 边界

Terraform `~> 1.6`，最终验收固定使用 **1.6.6**；AWS provider `~> 5.100`。所有 provider/remote-state 凭证为字面量 `test/test`，endpoint 必须是带显式端口的 loopback LocalStack root origin。禁止 inline role policy、SNS、`terraform_data`、mock/override、候选 VPC/AMI 发现、候选脚本和 `ignore_changes`。

```powershell
$env:PATH = "$env:TEMP\tfpro-terraform-1.6.6;$env:PATH"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```
