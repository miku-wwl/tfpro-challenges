# Challenge 44：S3 Object + IAM 合同的模块接口演进

难度：**95 / 100**；考试模式 **75 分钟**，首次完整学习 **130 分钟**。评级：**A**。

同一 release module 需要兼容两代 JSON 接口。V1 是 flat bundle；V2 将 artifact 与 identity 拆成嵌套合同并新增 payload digest。升级必须保留 module/resource identity，只允许真实内容与最小权限 policy 原地更新。

只修改 `starter/`：

1. 同时解析严格的 schema v1/v2，并归一化为一个 typed child-module contract。
2. 独立拒绝错误 schema/shape、重复 bundle、非法对象 key、digest 不匹配、非法或重复 IAM action。
3. 以 bundle name 驱动 module `for_each`；V1 JSON 重排与 object key 重排必须 clean。
4. 每个 child 创建 bucket、release object、consumer role、customer-managed policy 和 attachment；policy 只能用 `aws_iam_policy_document` 编译。
5. V1→V2 saved plan 必须精确包含两个 object update 与两个 policy update，bucket/role/policy ARN 和 object key 不得 rollover。
6. grader 外部 detach 一个 attachment 后，只能计划重建该 attachment。
7. provider 仅配置 `iam,s3,sts` LocalStack endpoints、字面量 `test/test` 与三项 skip flags。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

Full grader 固定使用 Terraform 1.6.6 与真实 LocalStack，执行 9 个 normal runs、V1 saved create/apply、远端 S3/IAM 合同读取、reorder clean、V2 精确 action map、ID 稳定性、attachment drift repair、saved destroy 与零残留。

候选只允许 S3 bucket/object 与 IAM role/policy/attachment 资源，以及 `aws_iam_policy_document` data source。
