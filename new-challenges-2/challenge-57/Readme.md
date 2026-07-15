# Challenge 57：Provider 锁文件升级与双区域 S3 模块路由

难度：**95 / 100**；考试模式 **75 分钟**，首次完整学习 **130 分钟**。评级：**A**。

一个双区域发布模块同时受 root 与 child module 的版本约束约束。仓库外部交付的旧 lock file 固定在
AWS provider `5.99.0`，已不满足 root 的 `5.100` patch line。你必须保留可审查的版本边界，证明
readonly 初始化会安全失败，再通过显式 upgrade 生成同时记录两层约束的新 lock selection。随后，同一
child module 要把每个发布物精确路由到 primary 与 replica provider slot，不能依赖隐式默认 provider。

只修改 `starter/`：

1. root 约束 Terraform `~> 1.6.0` 与 AWS provider `~> 5.100.0`；child 约束 Terraform 1.6 line、AWS `>= 5.90.0, < 6.0.0`，并声明 `aws.primary`、`aws.replica` configuration aliases。
2. 配置 `us-east-1` primary 与 `us-west-2` replica 两个 root provider；只使用 LocalStack `s3,sts` endpoints、字面量 `test/test`、path style 与三项 skip flags。
3. 严格编译 release JSON；独立拒绝错误 schema、空目录、错误 row shape、规范化重名、非法 identity、object key、payload 与错误区域合同。
4. 以 release name 驱动 module `for_each`，并显式传入两个 provider slot；每个 child 只创建两只 bucket 与两份同 key/content 的 object。
5. child 必须通过各 slot 的 `aws_caller_identity` 证明 provider 绑定；输出规范化目录、区域、caller、bucket/object identity 与八项精确地址合同。
6. grader 注入陈旧 lock file，要求 `terraform init -lockfile=readonly` 因 `5.99.0` mismatch 失败；随后 `init -upgrade` 必须选择 `5.100.0`，再次 readonly init 成功。
7. saved-plan JSON 必须证明四个 managed block 与两个 data block 的 `provider_config_key`；JSON 重排必须 clean，V2 只能更新 `api` 的两份 object。
8. grader 外部篡改 replica `worker` object 后，只能修复该 object；最后执行 clean plan、saved destroy、state 清空与 LocalStack 零残留检查。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

Full grader 固定使用 Terraform **1.6.6**，运行 **13 个**普通、无 mock 的 tests，并对 lock workflow、真实
双区域 S3 readback、provider routing、reorder、精确 rollout、drift repair、destroy 和 residue 做端到端审计。

对应大纲：**1a/1b/1c/1d/1e、2a/2b/2c/2d/2e、3c、5a/5b/5c**。
