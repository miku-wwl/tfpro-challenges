# Challenge 12：S3 Backend 迁移与跨 State 发布合同

难度：**96 / 100**；考纲契合度：**A**；考试模式 **85 分钟**，首次完整学习 **130 分钟**。

producer 与 consumer 是两个独立 root。producer 从 legacy S3 state key 迁移到 centralized key，
consumer 再通过 `terraform_remote_state` 的 S3 backend 读取一个最小发布合同。两边都在 LocalStack
创建真实 S3 workload；候选任务只修改 `starter/` 中的 Terraform HCL，不编写部署脚本。

## Terraform 任务

1. `producer` 与 `consumer` 是两个独立的 root module。先分别声明 partial
   `backend "s3" {}`；backend bucket、key 和 endpoint 由 grader 在 `terraform init`
   时注入。provider 与 remote-state backend 只能使用 LocalStack 的 `test/test`、
   loopback endpoint、path-style 和 skip flags。

2. 进入 `starter/producer`，规范化 CSV，只选择目标环境且 enabled 的服务，并使用
   service name 作为稳定的 `for_each` key。producer 创建一个 release bucket 和每个
   服务一个 S3 object；完成后执行 init、state migration、plan 和 apply。

3. producer 必须发布一个最小的 `release_contract` output，只包含 schema、environment、
   bucket name 与 object-key map。确认该 output 已写入 S3 backend state 后，才能继续
   consumer：

   ```hcl
   {
     schema_version = 1
     environment    = "prod"
     bucket_name    = "tfpro-c12-producer"
     object_keys = {
       api = "services/api.json"
     }
   }
   ```

4. 进入 `starter/consumer`，通过 S3 `terraform_remote_state` 读取 producer 的
   `release_contract`。不得复制 state JSON，也不得依赖 producer 的资源地址。consumer
   创建一个 receipt bucket 和稳定的 receipt objects，且 precondition 必须固定要求
   `schema_version == 1`。

5. 分别对两个 root 执行 clean plan，并验证输入重排不会改变资源地址。完成后按相反顺序
   销毁：先销毁 consumer，再销毁 producer。

`services-no-enabled.csv` 用于验证 producer 的 `check`：当没有符合环境且 enabled 的
服务时，配置应失败并显示对应的检查错误。

其中 `object_keys` 只保存服务名到 S3 object key 的映射，不要复制整个 producer state。

## 验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 会先执行 **5 个 Terraform 1.6.6 兼容的普通 plan tests**，不使用 mock/override；随后在
LocalStack 创建独立 backend bucket，真实执行 legacy-key apply、`init -migrate-state`、producer saved
plan、consumer saved plan、S3 payload 与 state ownership 检查、双 clean plan、逆序 saved destroy，最后
删除 backend state 并检查 S3 零残留。CLI orchestration 属于 grader，不是候选答题面。

## 考纲映射

- **1a–1e**：init backend、saved plan/apply、逆序 destroy、state migration 与 clean plan；
- **2a / 2c / 2d / 2e**：checks、CSV 转换、稳定 `for_each` 与复杂 output；
- **3b / 3c / 3d**：S3 remote state、非交互 workflow、跨配置合同；
- **5b / 5c / 5d**：AWS provider、LocalStack 凭证、endpoint 与 backend 排障。

AWS workload 只使用公开考试资源清单中的 `aws_s3_bucket`、`aws_s3_object` 和 S3 backend。
