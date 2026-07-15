# Challenge 33：Partial S3 Backend 环境隔离与安全发布

难度：**95 / 100**；考试模式 **70 分钟**，首次完整学习 **120 分钟**。评级：**A**。

同一套配置需要独立发布 `dev`、`stage`、`prod`。三个环境不能依赖 CLI workspace 的隐式状态，
而要由 grader 为同一个 partial S3 backend 注入三个独立 key。候选配置用显式 `environment`
输入构造稳定的 S3 bucket/object 发布图；自动化在 apply 前以 SHA256 和 plan JSON 审计每份 saved plan，
并把其中的资源名称、地址、Environment/Service tags 与目标环境合同显式绑定。

只修改 `starter/`：

1. 在 `terraform` block 中声明空的 `backend "s3" {}`；backend bucket、key、endpoint 和测试凭证只能由 `init -backend-config` 注入。
2. 规范化 `fixtures/services.csv`，独立拒绝错误 schema、空目录、重复服务、非法字段、非法布尔值和无启用服务。
3. `environment` 只允许 `dev`、`stage`、`prod`；以服务名作为 bucket/object 的稳定 `for_each` key，CSV 重排必须零变更。
4. 每个启用服务创建一个 `aws_s3_bucket.release` 和一个 `aws_s3_object.release`；名称、key、正文、metadata 与 tags 都携带显式环境合同。
5. AWS managed graph 只使用公开 Professional 清单中的 S3 bucket/object；provider 只配置 LocalStack `s3,sts` endpoint、字面量 `test/test` 与三项 skip flags。
6. 输出环境、排序服务 key、bucket、object key、owner 与 workspace-independent address contract。
7. grader 使用 Terraform 1.6.6 运行 8 个无 mock/override 的 canonical plan runs，再为三个独立 backend key 生成 saved plan；apply 前逐份记录 SHA256，并用 `terraform show -json` 审计精确 action/address/name/tags/environment 合同，只应用与原环境匹配的计划。随后验证三个精确 S3 state key、每个 root 的 state/output/resource 合同、真实 S3 payload/metadata/tags、reorder no-op、单环境 drift 不影响其余两个环境、clean plan、destroy 与零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

对应大纲：**1b/1c/1d、2a/2c/2d/2e、3b/3c**。CLI workspace 不是本题状态边界；环境隔离完全由 S3 backend key 与显式输入建立。
