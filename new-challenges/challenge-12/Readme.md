# Challenge 12：拆分配置、迁移 State 与自动化顺序

## 场景

一个单体基础设施配置已经拆成 `producer`（网络契约）和 `consumer`（应用清单）两个 root module。旧 producer state 仍在 legacy 路径。你需要把它迁移到集中式 local backend，并让 consumer 只通过 `terraform_remote_state` 使用 producer 的稳定输出。

本题用本地 backend 和 `terraform_data` 完整模拟生产流程；不会连接 AWS，也不需要凭证。

## 任务

只修改 `starter/`：

1. 为两个 root 声明 `backend "local" {}`，且不要把运行时绝对路径写死在 HCL 中。
2. producer 输出最小、稳定的 `network_contract`；不要向 consumer 暴露整个资源对象。
3. consumer 用 `data "terraform_remote_state"` 读取 grader 传入的 producer state 路径，并消费契约。
4. 修复资源身份，使 CSV 行顺序或显示名变化不会改变 producer/consumer 的 state 地址。
5. 完成 `automation/deploy.ps1`：按 producer → consumer 执行 `init`、保存 plan、apply 保存的 plan；所有命令必须非交互。
6. 演示从 legacy local backend 到 centralized local backend 的迁移，不能重建 producer 对象，也不能复制 JSON state 文件冒充迁移。
7. 最终两个 root 的重复 plan 必须为零变更。

## 验收

在仓库根目录运行：

```powershell
pwsh -NoProfile -File tmp2/challenge-12/tests/grade.ps1 -Candidate tmp2/challenge-12/starter
```

grader 会在系统临时目录创建独立工作副本和 backend，执行真实的 `init/apply/init -migrate-state`，不会污染 `starter/`。迁移后它会加入一个新服务；只有 producer 先 apply，consumer 才能读取到新契约，因此部署顺序也会被行为验证。

## 不变量

- producer 与 consumer 使用不同 state 文件，各自只拥有自己的资源。
- 迁移前后 producer 的资源 ID 和 state 地址保持不变。
- consumer 只能读取 `network_contract`，不能依赖 producer 内部资源地址。
- 部署顺序是 producer → consumer；销毁顺序应反向进行。
- 自动化使用 `-input=false`、保存 plan，并 apply 同一个 plan 文件。
- state 路径由 backend config/变量注入，代码中没有机器相关绝对路径。

## 安全边界

- 禁止加入 AWS provider、真实 backend、访问密钥或网络 provisioner。
- local state 可能包含敏感数据；本题数据均为虚构值，临时 state 在验收结束后删除。
- 不要手工编辑或直接复制 state；只能通过 Terraform backend migration 完成迁移。

## Terraform Professional objective

覆盖 Professional 大纲中的 state/backend 操作、配置拆分、跨配置数据共享、非交互式 workflow、plan/apply 一致性，以及安全的变更顺序与故障恢复。
