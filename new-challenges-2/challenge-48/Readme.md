# Challenge 48：双 S3 State 制品合同与 IAM 消费者

难度：**95 / 100**；考纲契合度：**A**。建议考试用时 **75 分钟**，完整学习与复盘 **140 分钟**。

本题包含两个独立 root。`foundation` 发布 S3 制品和版本化输出合同；`delivery` 只能通过 S3 `terraform_remote_state` 消费该合同，并把 grant manifest 编译为最小 IAM 访问策略。两个 state key、依赖方向和销毁顺序都必须显式且可审计。

## 任务

只修改 `starter/foundation` 与 `starter/delivery`：

1. 两个 root 都声明空的 partial S3 backend，分别使用 `foundation/terraform.tfstate` 与 `delivery/terraform.tfstate`；backend bucket/config 由 grader 注入。
2. Foundation 严格验证 artifact catalog，以 name 为稳定 key，只创建 `aws_s3_bucket` 与两个 `aws_s3_object`，并输出 contract version、producer run id、revision、bucket、artifact ARN/digest map 与 fingerprint。
3. Catalog 数组重排必须 no-op；v1 → v2 保留地址，只原地更新两个对象。
4. Delivery 使用 S3 `terraform_remote_state`，远端配置必须包含 `test/test`、path style、三项 skip flag 与 loopback S3 endpoint。禁止读取 foundation 文件或枚举 S3 来伪造合同。
5. 严格验证远端 contract、期望 revision 和 grant manifest。用 `aws_iam_policy_document` 生成最小 `s3:GetObject` 权限，只创建 IAM role、managed policy 与 attachment。
6. Foundation 和 delivery provider 分别只暴露所需的 LocalStack `s3/sts` 与 `iam/sts` endpoint。

## 不变量

- Terraform `~> 1.6`，最终验收固定使用 **1.6.6**；AWS provider `~> 5.100`。
- 禁止 SNS、`terraform_data`、mock/override、VPC 资源/发现、候选脚本和 `ignore_changes`。
- Stale delivery revision 必须失败；重排 artifact/grant 输入必须严格 no-op。
- 销毁顺序固定为 delivery → foundation，不能让消费者在生产者之前失去合同。

## 验收

Grader 运行 foundation 8 个、delivery 7 个普通 canonical runs，并审计两份 state 的 saved plans。完整模式还会验证精确 state keys、S3 对象内容漂移、IAM attachment 漂移、v2 合同传播、stale consumer 拒绝、最终 clean plans、逆依赖 saved destroy，以及 IAM/S3/state bucket 零残留。

```powershell
$env:PATH = "$env:TEMP\tfpro-terraform-1.6.6;$env:PATH"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```
