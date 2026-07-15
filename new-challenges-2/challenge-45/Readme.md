# Challenge 45：Partial S3 Backend 与跨 State 发布合同

难度：**95 / 100**；考试模式 **80 分钟**，首次完整学习 **135 分钟**。评级：**A**。

producer 与 consumer 是两个独立 root。两边都使用 grader 注入的 partial S3 backend；producer state 从 legacy key 迁移到 canonical key，consumer 只能通过 S3 `terraform_remote_state` 消费最小发布合同，并用真实 `aws_s3_object` 物化 receipt。

只修改 `starter/`：

1. 两个 root 都声明空的 partial `backend "s3" {}`；禁止 local backend 和候选脚本。
2. producer 规范化 payload map，以 semantic name 驱动 S3 objects，独立拒绝空目录、非法/重复 name 与空 payload。
3. producer 发布 schema v1 合同：run/release identity、bucket、对象 key+SHA256 map 和顺序无关 fingerprint。
4. consumer 完整配置 LocalStack S3 remote state（字面量 `test/test`、path style、三项 skip flags），只能读取 producer output。
5. consumer 独立验证 schema、producer run、expected release、required artifact set、key/digest，并为每个 artifact 创建 JSON receipt object。
6. V1 map 重排必须 clean；V1→V2 必须精确更新两个 producer objects，再精确更新两个 consumer receipts。
7. grader 制造单 receipt 内容漂移时，repair plan 只能更新该 object；最终必须 consumer→producer 反向销毁并清理 backend state。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 在官方 Terraform 1.6.6 上运行 7 个 normal producer tests、两 root fmt/init/validate、真实 LocalStack backend bucket、legacy→canonical state migration、saved plans、remote-state contract upgrade、reorder/drift/clean、reverse saved destroy 和全部 S3 零残留。

候选 AWS workload 仅允许 `aws_s3_bucket`、`aws_s3_object`，以及 S3 backend/`terraform_remote_state`。
