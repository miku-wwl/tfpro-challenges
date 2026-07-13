# Challenge 13：复杂类型、动态 HCL 与分层契约

## 场景

平台团队从 CMDB CSV 读取服务，从 JSON 目录读取 owner 元数据，再生成确定性的部署目录。输入来自不同团队，错误可能出现在单个字段、跨文件引用或全局容量预算中。你需要在最合适的层次失败，并确保秘密派生值不会出现在普通 CLI 输出中。

本题只使用 Terraform 内建函数和 `terraform_data`，不访问云。

## 任务

只修改 `starter/`：

1. 把 CSV 字符串显式转换为 `number`/`bool`，只选择目标环境中启用的服务。
2. 使用服务名作为稳定 `for_each` key；CSV 重排行不能改变资源身份或输出顺序。
3. 为 `target_environment` 和复杂对象 `policy` 编写 variable validation。
4. 使用 resource preconditions 拒绝非法端口、未知 owner 和不允许的 tier。
5. 使用 postcondition 验证生成的规范化 endpoint。
6. 使用 `check` block 验证所有服务总容量不超过策略预算；这是跨实例、非阻塞式运行状况断言。
7. 输出排序后的服务 key、按 owner 分组的服务目录、完整 typed profile。
8. 用 `token_salt` 与 owner seed 派生部署 token，并将整个 output 标为 sensitive。

## 验收

```powershell
pwsh -NoProfile -File tmp2/challenge-13/tests/grade.ps1 -Candidate tmp2/challenge-13/starter
```

测试包含默认输入、CSV 重排、非法环境、非法端口、未知 owner、非法 tier 和超预算负向用例。
grader 会把 canonical tests 临时复制到 candidate 内部再调用 `terraform test`，结束后自动删除；这是因为 Terraform 要求 test directory 位于被测配置目录之内。

## 不变量

- 稳定身份来自业务 key，不来自行号或 CSV 顺序。
- `port`、`capacity`、`enabled` 在进入资源前已经是正确类型。
- 单字段/输入形状由 validation 处理；逐行关系由 precondition 处理；聚合预算由 check 处理。
- 所有公开 collection 输出顺序确定。
- token 可存在 state 中，但 CLI 必须把对应 output 隐藏为 sensitive；不要把它当作 secret manager。

## 安全边界

- fixtures 中的 seed 和 salt 都是假数据。
- 禁止加入 provisioner、外部命令、真实凭证或云 provider。
- sensitive 只控制显示，不会从 state 中移除数据；生产环境应改用秘密管理系统。

## Terraform Professional objective

覆盖 Professional 大纲中的复杂类型约束、collection/for expressions、动态资源实例、validation、precondition/postcondition、check blocks、sensitive data 与可测试模块契约。
