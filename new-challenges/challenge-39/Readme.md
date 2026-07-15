# Challenge 39：S3 Remote Backend 与跨 State 发布合同

难度 **96/100**；考试模式建议 **70 分钟**，首次学习建议 **125 分钟**。

## 场景

producer 必须把 state 存到真实 LocalStack S3 backend，并通过 DynamoDB 加锁；consumer 只能通过 `terraform_remote_state` 读取一个显式版本合同，再向 producer 管理的 artifact bucket 发布对象。backend bucket 和 lock table 属于平台 bootstrap，不得写进 producer 自己的 state。

## 任务

仅修改 `starter/`：

1. producer 使用空的 partial `backend "s3" {}`，禁止在源码硬编码 backend 地址或凭证。
2. producer 创建启用 versioning 的 artifact bucket，并发布 `delivery_contract` v1。
3. consumer 使用 Terraform 1.6 兼容的 S3 remote-state 配置，包括 LocalStack endpoint、path style、`test/test` 与三个 skip 开关。
4. consumer 用七个独立 precondition 分别验证合同版本、region、state bucket、state key、artifact bucket、versioning 和 producer run id；每个失败 fixture 只破坏一个语义。
5. consumer 创建 `releases/<release_id>.json`；正文必须精确包含 `contract_version`、`release_id`、`producer_run_id`、`managed_by` 四个字段，并与 remote-state contract 一致。
6. producer 与 consumer 自身都必须拒绝带路径、userinfo、越界端口、CR/LF 或非 loopback 的 endpoint，并以 RE2 `\z` 锁定输入结尾。
7. candidate 只允许 `producer/` 与 `consumer/` 两个 Terraform root；禁止嵌套 module/provider。grader 会对白名单中的 variable、data、resource、locals 和 output 做精确顶层结构审计。

运行：

```powershell
pwsh ./tests/grade.ps1
```

Canonical tests 精确包含 producer 4 个、consumer 10 个 run。grader 会临时创建 backend bucket 与 DynamoDB lock table；producer 与 consumer 的首次 saved-plan JSON 必须分别只包含两个预期的 `create`，禁止额外 managed resource。真实流程还会验证 consumer-before-producer 失败、远端 state、release 正文与标签、saved plan stale 拒绝、对象 drift 恢复、逆序 destroy，以及聚合式零残留清理。
