# Challenge 22：Partial S3 Backend 迁移与跨 State 发布合同

难度：**96 / 100**；考纲契合度：**A**
考试模式建议：**70 分钟**；完整学习与复盘：**125 分钟**

## 场景

一个制品 producer 已经用 local state 发布了版本化对象，但团队现在要求把它迁移到共享的 S3 backend。
独立的 consumer 不能引用 producer 的资源，只能通过 S3 `terraform_remote_state` 读取显式版本合同，并发布
可审计的消费回执。你需要在不重新创建既有资源的前提下完成迁移，再用 saved plan 推进 v1→v2，最后按
依赖逆序销毁两个 state。

本题只要求修改 Terraform HCL。backend bucket 与锁表由平台（grader）在配置之外创建；它们不属于任何
workload state。

## 目录

```text
starter/
  producer/              # local→partial S3 backend；发布 release_contract
  consumer/              # S3 remote state；验证合同并发布 receipt
fixtures/
  producer.backend.example.hcl
  consumer.backend.example.hcl
  release-v1.tfvars.json
  release-v2.tfvars.json
tests/
  producer.tftest.hcl    # 9 个 Terraform 1.6 兼容 run
  grade.ps1              # 静态审计 + LocalStack E2E
```

## 任务

只修改 `starter/`，完成两套独立 root module 中的实质 TODO：

1. producer 与 consumer 都声明空的 partial `backend "s3" {}`；bucket、key、region、endpoint、凭证和
   历史锁表参数只能通过 `terraform init -backend-config=...` 注入。
2. producer 把 payload map 规范化为逻辑名称稳定寻址的 release map，并分别拒绝空 catalog、不安全名称和
   空白 payload。
3. producer 创建启用 versioning 的 S3 bucket，以 `for_each` 发布 `releases/<name>.txt`；内容、
   `source_hash` 及 Release/RunId/Sha256 标签必须一致。
4. producer 只输出一个 `release_contract`：合同版本、producer run id、release 版本、bucket、对象 key/digest
   map 与 catalog fingerprint。consumer 不得越过合同读取 producer 内部资源。
5. consumer 使用 Terraform 1.6 兼容的 `terraform_remote_state(s3)` 配置，显式提供 loopback S3 endpoint、
   path style、`test/test` 与三个 skip flags。
6. consumer 用独立 precondition 验证合同版本、producer 身份、期望 release、精确对象集合及 SHA-256 形状。
7. consumer 创建启用 versioning 的 receipt bucket，并按远端对象的稳定 key 发布 JSON 回执；输出消费合同。

## 工作流不变量

- `required_version = "~> 1.6"`，AWS provider `~> 5.100`；canonical tests 禁止
  `mock_provider`、`override_resource`、`override_data`，可直接由 Terraform 1.6 执行。
- AWS workload 以官方清单中的 S3 bucket、S3 object 为核心；bucket versioning 是 S3 backend 与 state
  recovery 场景的配套行为。provider 只配置 `s3`、`sts` LocalStack endpoint、字面量 `test/test`、path style
  与三个 skip flags。
- endpoint 必须是带 1–65535 显式端口、无路径/查询/userinfo/CR/LF 的 loopback root origin。
- grader 先以 local backend 对 producer 执行 saved plan/apply，再执行 `init -migrate-state`；迁移后 resource
  address 集合必须不变且 plan 必须为零变更。禁止 `state push -force`、手工修改 state 或手工插入锁记录。
- consumer 只能在 producer remote state 已发布后规划；升级时分别保存并应用 producer、consumer plan。
- 销毁顺序固定为 consumer→producer→平台 backend。任何 candidate 配置都不得管理 backend bucket 或锁表。

## 关于 DynamoDB 锁

grader 为 Terraform 1.6 考试时代的 S3 backend 创建并正常使用外部 DynamoDB lock table。当前 Terraform 已将
该锁机制标记为 deprecated；本题只保留它来复现 1.6 backend 合同，不考查锁表行、`force-unlock` 或任何
LocalStack workaround。候选配置也不管理该表。

## 运行

先启动提供 `s3,dynamodb,sts` 的本地 Docker LocalStack，然后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ./tests/grade.ps1
```

只运行静态检查、fmt/init/validate 与 9 个 Terraform 1.6 canonical runs：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ./tests/grade.ps1 -UnitOnly
```

grader 始终在临时副本中工作，不会把 `.terraform`、state、plan 或 lockfile 写入 starter。完整 E2E 会验证
producer local saved-plan、S3 backend 迁移、跨 state 合同、consumer saved-plan、v2 升级、clean plan、
逆序 destroy 和 LocalStack 零残留。
