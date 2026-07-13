# Terraform Professional Challenges 9–18

这组练习按照 Terraform Authoring & Operations Professional 的生产级实操深度设计，
难度基准为“完整 Professional 考试 = 100”。平均难度约 90，重点接近原
Challenge 3（provider/auth/module）与 Challenge 5（state/backend/refactor）的复杂度。

AWS 题需要本机 LocalStack 的 `s3,sts,ec2,sns` 服务。仓库 Compose 默认服务集已经
包含这些服务，可先运行 `pwsh ./scripts/localstack-up.ps1`。

## 题目与难度

| Challenge | 分数 | 建议时间 | 主题 |
|---|---:|---:|---|
| 9 | 90 | 75m | 同一 state 中完成 import、moved、state rm 与 drift 恢复 |
| 10 | 91 | 90m | 单体 count 到多模块 for_each 的零替换迁移 |
| 11 | 89 | 75m | 双区域 provider alias、模块 provider contract 与认证诊断 |
| 12 | 90 | 80m | 拆分 state、backend migration、remote state 与自动化顺序 |
| 13 | 88 | 70m | CSV/JSON 复杂类型、validation、conditions、checks 与 sensitive |
| 14 | 86 | 70m | Terraform/provider/module 版本、lockfile upgrade 与故障定位 |
| 15 | 89 | 75m | CSV 驱动的 AWS 网络与稳定安全规则身份 |
| 16 | 91 | 90m | saved plan、JSON 审计、detailed-exitcode、state 备份与 drift 恢复 |
| 17 | 94 | 90m | 双区域嵌套模块、provider graph 与无替换重构 |
| 18 | 96 | 120m | 双 root、remote-state contract、双区域服务目录综合题 |

## Professional 大纲覆盖

| 官方领域 | 主要 Challenge |
|---|---|
| 1. Manage resource lifecycle | 9、10、12、16、18 |
| 2. Develop and troubleshoot dynamic configuration | 13、15、18 |
| 3. Develop collaborative Terraform workflows | 12、14、16、18 |
| 4. Create, maintain, and use modules | 10、17、18 |
| 5. Configure and use providers | 11、14、15、17、18 |
| 6. HCP Terraform | 不伪造本地服务；该领域按官方形式使用选择题复习 |

## Starter 合同

- 只修改各题的 `starter/`，不要修改 fixtures 或 canonical tests。
- 每题都有 `lab.yaml`、中文 `Readme.md` 和自动 grader。
- starter 保留 TODO、错误映射或不完整流程；它们应在完成前验收失败。
- 出题期间每道题都曾用完整参考实现执行 `fmt/init/validate/test` 或专项 state
  grader；打包时参考实现已移除，只留下 starter。
- Challenge 11、15、17、18 默认连接本机 LocalStack，并保留 mock provider 单元测试。
- stateful 题在题目自身或系统临时目录创建隔离工作区，grader 完成后清理。

进入任一 challenge，先阅读该题 `Readme.md`，再使用其中的 `tests/grade.ps1`
命令验收。AWS 题只允许 loopback LocalStack endpoint，不要对真实云账号执行。

## 版本说明

配置只使用 Terraform 1.6 可用的语言功能，`required_version` 使用 `~> 1.6`，因此
当前 1.x CLI 可运行。mock provider 是测试隔离能力；使用当前仓库的 Terraform 1.14
可以直接运行全部 grader。若严格锁定 CLI 1.6.6，可直接使用 LocalStack 端到端路径
验收 AWS 配置，候选 HCL 的考点不变。
