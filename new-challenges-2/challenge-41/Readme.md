# Challenge 41：既有发布资源接管与零替换模块化迁移

难度：**95 / 100**；考试模式 **70 分钟**，首次完整学习 **125 分钟**。评级：**A**。

旧 root 以 `count` 管理 `api`、`worker` 的发布 bucket、manifest object 与 publisher IAM role。现在必须迁移到以服务名为稳定 key 的 child module。真实资源不得重建；迁移意图必须保存在 HCL 中，并在同一 state lineage 上证明没有 create、update、delete 或 replace。

只修改 `starter/`：

1. 规范化 `fixtures/services.json`，独立拒绝错误 schema、空目录、重复 name、非法字段和无 enabled 服务。
2. 只部署 enabled 服务，以规范化 name 驱动 module `for_each`；输入重排必须零地址变化。
3. child 创建 `force_destroy` bucket、固定 key 的 manifest object 与 EC2 trust publisher role，并保持 legacy 名称、内容和六项标签合同。
4. 用恰好 **6 个** `moved` blocks 将两个服务的三类 legacy count 地址迁到 module 地址；禁止 `terraform state mv`。
5. 输出排序后的 service keys、bucket/object/role 合同与六个精确资源地址。
6. AWS provider 只配置 `iam,s3,sts` LocalStack endpoints，凭证必须是字面量 `test/test`，并启用三项 skip flags。

执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 固定使用官方 Terraform 1.6.6 normal tests，并真实 apply legacy fixture、移交 local state、审计 saved-plan JSON 的 `previous_address` 与全量 `no-op`、apply 地址迁移、验证 reorder clean、制造单 object 内容漂移并精确修复、审计 saved destroy，最后确认 S3/IAM 与 state 均零残留。

允许候选 AWS 类型仅为 `aws_s3_bucket`、`aws_s3_object`、`aws_iam_role` 和 `aws_iam_policy_document` data source。
