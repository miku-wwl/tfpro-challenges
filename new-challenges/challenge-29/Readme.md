# Challenge 29：双区域嵌套模块数据与事件复制

难度：**97 / 100**　建议用时：**120 分钟**

## 场景

服务目录来自 CSV。每个启用的 prod 服务必须在 primary 和 DR 各获得一个 S3 artifact
bucket、一张 DynamoDB catalog table 和一个 SNS topic。root → replication → regional
是两层 child module；每一层都必须正确声明和传递 provider alias。DR 还要消费 primary
topic ARN 作为显式故障转移合同。

## 任务

1. 规范化并过滤 CSV，使用服务名作为稳定 key；重排行不得改变资源地址。
2. 验证环境、run id、两个 region；禁止 primary/dr 相同。
3. root 显式映射 `aws.primary`、`aws.dr` 到 replication module。
4. replication module 声明两个 aliases，并把正确 provider 继续传给 regional modules。
5. DR module 消费 primary 输出、声明依赖策略，不能直接引用孙模块资源。
6. 每个 regional module 用三个资源 block + `for_each` 创建 S3/DynamoDB/SNS。
7. 输出双区域合同、排序服务 key、按 owner 分组的 service list。
8. LocalStack apply 后重复 plan 为零，destroy 不遗留 bucket/table/topic。

## 验收

```powershell
pwsh ./tests/grade.ps1
```

grader 同时运行 mock provider contract tests 和真实 LocalStack E2E。provider 仅允许
loopback endpoint 与 `test/test`，S3 必须使用 path-style。

## Professional 大纲

覆盖复杂 collection、nested module interface、configuration_aliases、provider graph、
dependency graph、可复现资源身份与 provider troubleshooting。

