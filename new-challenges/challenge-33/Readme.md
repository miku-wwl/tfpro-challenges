# Challenge 33：CLI Workspace 隔离与安全环境晋级

难度：**95 / 100**　建议用时：**110 分钟**

## 场景

同一套发布基础设施要依次服务 `dev`、`stage`、`prod`。服务目录来自 CSV，每个启用
服务需要一个 S3 发布 bucket 和一个 SNS 发布 topic。团队决定使用 Terraform CLI
workspace 隔离三套状态，但当前实现还没有建立资源身份、状态边界和晋级安全合同。

## 任务

1. 解析并规范化 CSV，仅发布启用的服务，以服务名作为稳定 `for_each` key。
2. 拒绝空目录、非法字段和重复服务名；CSV 重排行不能改变资源地址。
3. 只允许 `dev`、`stage`、`prod` 三个 CLI workspace。
4. bucket、topic、tags 和输出合同必须显式包含 `terraform.workspace`。
5. 使用 LocalStack 的 S3、SNS、STS endpoint，以及字面量 `test/test` 测试凭证。
6. 证明 dev 生成的 saved plan 不能在 stage 应用。
7. 分别创建三个 workspace，证明状态、漂移检测和重复 plan 相互隔离。
8. 完成后销毁每套资源并删除三个 workspace，不留下 LocalStack 资源。

## CSV 合同

`fixtures/services.csv` 包含 `service,owner,enabled` 三列：

- `service`、`owner` 只允许小写字母、数字和连字符；
- `enabled` 只能是 `true` 或 `false`；
- 服务名在整个目录中必须唯一，包括 disabled 行以及一启一禁的组合；
- 只有启用行参与资源创建，但所有行都必须通过格式校验，且目录不能没有启用服务。

## 验收

请确保 LocalStack 已启动，然后运行：

```powershell
pwsh ./tests/grade.ps1
```

grader 会精确运行 8 个 mock-provider tests：正常目录、重排行、非法 service、空 owner、
非法 enabled、全目录重复、空目录及非法 CLI workspace；随后执行真实的 workspace/
saved-plan/drift/cleanup 端到端流程。它只接受 loopback LocalStack endpoint。

## Professional 大纲

覆盖 CLI workflow、workspace state isolation、saved plan、drift、稳定资源身份、复杂
collection、输入验证、LocalStack provider 安全配置与可重复清理。
