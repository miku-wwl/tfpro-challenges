# Challenge 28：双 S3 State、双 Provider 与版本传播合同

难度：**97 / 100**；考纲契合度：**A**；考试模式 **90 分钟**，首次完整学习 **145 分钟**。

`foundation` 与 `application` 是两个独立 root/state。foundation 通过 primary/DR provider aliases 发布两份 S3 platform manifest 和一个最小版本化 output 合同；application 用 S3 `terraform_remote_state` 消费合同，再根据 CSV 把应用展开到 primary、DR 或两边。platform revision 必须按 foundation → application 顺序传播，销毁必须反向进行。

只修改 `starter/` 中的 Terraform HCL；不得提交 backend 凭证、候选脚本或手工 state 操作。

## Foundation 任务

1. 声明空的 partial `backend "s3" {}`；backend 参数只由 grader 注入。
2. 配置 `aws.primary` 与 `aws.dr`，使用字面量 `test/test`、S3 path-style、S3/STS loopback endpoints 和三项 skip flags。
3. 只用公开清单中的两个 `aws_s3_bucket` 和两个 `aws_s3_object`；每个 provider slot 管理自己的 bucket/manifest。
4. manifest 使用 canonical JSON、`etag`、`source_hash` 和 revision tags。
5. 输出 `platform_contract`：contract version、revision、run ID，以及 primary/dr 的 region、bucket、manifest key。
6. output precondition 阻断相同 primary/DR regions。

## Application 任务

1. 使用独立 partial S3 backend，并以 S3 `terraform_remote_state` 读取 foundation state；远端配置显式使用 test/test、path-style、三项 skip flags 和 loopback S3 endpoint。
2. 规范化 CSV；过滤目标环境及 enabled 行，将 `both` 展开为 primary/dr，以 `application@location` 为稳定 key。
3. 独立阻断未知 location、重复展开 key、非法 name/owner/port、错误 contract version/revision/run/region。
4. 使用两个静态 module blocks；分别映射 `aws.primary` 与 `aws.dr`，禁止动态 provider 选择。
5. child module 使用公开清单中的 `aws_caller_identity`、`aws_s3_bucket` 和 `aws_s3_object`，发布包含 platform revision 的 receipt。
6. 输出排序 deployment keys、完整区域合同和 owner 分组。

## 操作合同

grader 会：

1. 外部创建 LocalStack S3 backend（Terraform 1.6 锁表也仅由 grader 创建）；
2. saved-plan apply foundation revision 1，再 saved-plan apply application；
3. 验证 reordered CSV no-op；
4. 证明 application 不能提前期望 revision 2；
5. foundation saved-plan 发布 revision 2 后，旧 application 期望必须失败；
6. application saved-plan 精确更新四个 receipt objects；
7. 两个 root clean；
8. saved destroy application → foundation，并检查全部 workload bucket 零残留。

候选配置不管理 DynamoDB；锁表只是 Terraform 1.6 LocalStack backend 的外部测试设施。本题不使用 VPC/subnet/SNS/`terraform_data`。

## 验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

canonical suite 使用 Terraform **1.6.6** 的 **8 个普通 foundation plan runs**，无 `mock_provider` / `override_*`；application 的 remote-state/provider 行为由真实 E2E 验证。

仅运行静态检查、两个 root 的 init/validate 和 canonical tests：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```

## 考纲映射

- **1b / 1c / 1d**：saved plan、apply 和 ordered destroy；
- **2a / 2b / 2c / 2d / 2e**：contract preconditions、caller identity、CSV functions、`for_each` 与复杂 outputs；
- **3a / 3b / 3c / 3d**：version constraints、S3 backends、自动化流程和跨 state 数据；
- **4a / 4b**：创建并调用 provider-aware child module；
- **5b / 5c / 5d**：provider alias routing、认证与排错。
