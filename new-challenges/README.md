# Terraform Professional Challenges 9–18

这组练习按照 Terraform Authoring & Operations Professional 的生产级实操深度设计，
难度基准为“完整 Professional 考试 = 100”。平均难度约 93，重点接近原
Challenge 3（provider/auth/module）与 Challenge 5（state/backend/refactor）的复杂度。

Challenge 9–40 中原 B 级题目的 A 级整改与端到端证据见 [VERIFICATION.md](./VERIFICATION.md)。

AWS 题需要本机 LocalStack 的 `s3,sts,ec2,sns` 服务。仓库 Compose 默认服务集已经
包含这些服务，可先运行 `pwsh ./scripts/localstack-up.ps1`。

## 题目与难度

| Challenge | 分数 | 建议时间 | 主题 |
|---|---:|---:|---|
| 9 | 90 | 75m | 同一 state 中完成 import、moved、state rm 与 drift 恢复 |
| 10 | 91 | 90m | 单体 count 到多模块 for_each 的零替换迁移 |
| 11 | 95 | 70m | 双区域 provider alias、caller identity 与真实 bucket 路由 |
| 12 | 96 | 85m | S3 backend migration、跨 state 发布合同与逆序销毁 |
| 13 | 88 | 70m | CSV/JSON 复杂类型、validation、conditions、checks 与 sensitive |
| 14 | 86 | 70m | Terraform/provider/module 版本、lockfile upgrade 与故障定位 |
| 15 | 95 | 75m | subnet data source、稳定安全规则身份与真实 drift 修复 |
| 16 | 95 | 75m | saved plan、refresh-only、state pull 与真实 S3 drift 修复 |
| 17 | 94 | 90m | 双区域嵌套模块、provider graph 与无替换重构 |
| 18 | 97 | 110m | 双 S3 state、双区域 provider 分支与 service object 综合题 |

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
- Challenge 11、12、15、16、18 使用 Terraform 1.6 普通 tests 与真实 LocalStack；Challenge 17 仍保留隔离的 mock provider tests。
- stateful 题在题目自身或系统临时目录创建隔离工作区，grader 完成后清理。

进入任一 challenge，先阅读该题 `Readme.md`，再使用其中的 `tests/grade.ps1`
命令验收。AWS 题只允许 loopback LocalStack endpoint，不要对真实云账号执行。

## 版本说明

配置只使用 Terraform 1.6 可用的语言功能，`required_version` 使用 `~> 1.6`。Challenge
11、12、15、16、18 的 canonical tests 与端到端 grader 已直接在 Terraform 1.6.6 上验证；
AWS 调用全部指向本机 LocalStack。Challenge 17 的旧 mock tests 需要较新的 Terraform CLI。
