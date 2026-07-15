# Challenge 46：Saved Plan 制品、语义稳定发布与漂移恢复

难度：**95 / 100**；考纲契合度：**A**。建议考试用时 **65 分钟**，完整学习与复盘 **120 分钟**。

平台团队用无序 JSON catalog 发布两份 S3 制品。你需要把输入编译成稳定资源图，并让升级、漂移检查、修复与销毁都能够通过 saved-plan JSON 精确审计。候选实现只能包含 Terraform HCL；所有 AWS 请求均发送到本机 Docker LocalStack。

## 任务

只修改 `starter/`：

1. 严格验证 catalog 的顶层字段、schema、release、artifact 字段集合、唯一 name/key、安全 key、owner 与非空 content；非法输入必须在 plan 阶段被明确拒绝。
2. 以规范化后的 artifact name 作为 `for_each` key。仅调整 JSON 数组顺序时，资源地址、输出和 plan 都必须保持不变。
3. 只创建一个 `aws_s3_bucket` 和按 artifact 寻址的 `aws_s3_object`。Bucket 必须可安全清理；不得增加 versioning、SNS 或其他候选资源。
4. 对象同时使用语义 digest、`source_hash` 与 `etag` 跟踪本地内容和真实远端漂移，不得用 `ignore_changes` 隐藏差异。
5. 输出 `release_contract`：账户、bucket、排序后的对象地址、key/digest/owner map，以及与输入排列无关的 `semantic_fingerprint`。
6. AWS provider 只能配置 `s3`、`sts` loopback endpoint，凭证必须是字面量 `test/test`，并保留三项安全 skip flag。

## 不变量

- Terraform 必须为 `~> 1.6`；官方验收固定使用 **1.6.6**，AWS provider 为 `~> 5.100`。
- 禁止 `count`、候选脚本、mock/override、`terraform_data`、SNS、VPC 资源或发现式数据源、`-target`、`-refresh=false` 与 `ignore_changes`。
- v1 → v2 只能原地更新两个既有 object，不能 create、delete 或 replace。
- Grader 审计 saved plan 的 JSON 和 SHA-256 后，只应用同一个 plan 文件。

## 验收

Grader 执行 8 个无 mock 的 Terraform 1.6.6 canonical runs，然后验证：v1 apply 后 clean plan；重排严格 no-op；v2 精确两项 update；内容漂移与 tag 漂移能被 refresh-only 观察且不修改远端；普通 saved plan 精确修复；最终 saved destroy 和 S3 零残留。

```powershell
$env:PATH = "$env:TEMP\tfpro-terraform-1.6.6;$env:PATH"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```
