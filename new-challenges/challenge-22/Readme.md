# Challenge 22：远端状态迁移与有序发布

难度：**97/100**　建议时限：**180 分钟**

一个 producer 仍在使用 legacy local backend；consumer 需要通过 `terraform_remote_state` 消费它的版本化合同。你要先用 Terraform 创建 LocalStack S3 backend 与 DynamoDB lock table，再迁移已有 state，最后完成只应用保存 plan、且按依赖逆序销毁的发布脚本。

## 目录与任务

只修改 `starter/`：

- `bootstrap/`：创建唯一 S3 bucket 和 DynamoDB table。table 的 partition key 必须是字符串 `LockID`；bucket 要能在最终精确清理。
- `producer/`：把 legacy `backend "local"` 改为部分配置的 `backend "s3" {}`，保留 `terraform_data.contract` 的身份，并输出 `platform_contract` schema v2。
- `consumer/`：自身也使用 S3 backend；通过 S3 `terraform_remote_state` 读取 producer state。远端读取必须显式使用 test/test、skip flags、path-style 与 loopback S3 endpoint。
- `scripts/release.ps1`：Deploy 时按 producer→consumer 顺序执行 `plan -out` 和 `apply <saved-plan>`；Destroy 时严格 consumer→producer，并记录顺序。

## 必做迁移流程

1. 先 apply `bootstrap/`，取得 bucket/table。
2. 用 local backend apply 一次 producer，建立 legacy state。
3. 将 producer backend 改为 S3，生成 backend config，然后执行：

```powershell
terraform -chdir=producer init -migrate-state -force-copy -backend-config=producer.backend.hcl
```

4. 确认原地址仍在 state，S3 中出现 producer state object。
5. 用发布脚本 Deploy，检查 consumer 观察到新 `release_id`；再次 plan 必须 clean。
6. 用发布脚本 Destroy，最后销毁 bootstrap。不能先删除 producer state，否则 consumer 将无法刷新依赖。

`fixtures/local-backend.tf` 是 grader 创建 legacy state 时使用的基线，候选实现不应复制它作为最终 backend。

## Terraform 1.14 + LocalStack backend 说明

本题在 Terraform 1.14 实测 backend config 使用：

```hcl
use_path_style = true
endpoints = {
  s3       = "http://localhost:4566"
  dynamodb = "http://localhost:4566"
}
```

并启用三个 `skip_*` 选项。`dynamodb_table` 在新版 Terraform 已标记为 deprecated，但仍被本题刻意使用来训练 Professional 大纲中的旧环境迁移与锁诊断；不要把它误写成 provider 的 `endpoints` block。

所有 AWS 流量只能去 loopback LocalStack，凭证固定 `test/test`。本题不接受真实 bucket、账号、profile 或 access key。

## 验收

```powershell
pwsh ./tmp2/challenge-22/tests/grade.ps1
```

grader 在安全临时目录中使用唯一名称，真实执行 bootstrap、local apply、`-migrate-state`、保存 plan 发布、remote-state 消费、clean plan、有序 destroy，并直接确认 S3/DynamoDB 已清理。
