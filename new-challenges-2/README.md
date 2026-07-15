# Terraform Professional Challenges 41–60

这组练习面向 Terraform Authoring & Operations Professional 的 AWS 实操版本。统一目标难度为
**95 / 100**，考纲契合度为 **A**；AWS 端到端验证只连接本机 Docker LocalStack。

题目资源与工作流以 HashiCorp 当前公布的
[Terraform Professional exam content list](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)
为边界。候选配置只使用清单中的 AWS 资源、data source、S3 backend 与
`terraform_remote_state`；LocalStack Community 不支持的 Auto Scaling API 不作为运行时依赖。

## 题目矩阵

| Challenge | 难度 | 契合度 | 主题 |
|---|---:|---:|---|
| 41 | 95 | A | 既有 S3/IAM 发布资源接管与 `moved` 模块化迁移 |
| 42 | 95 | A | 三 Provider slot、S3/IAM 路由与身份审计合同 |
| 43 | 95 | A | JSON 驱动 IAM 权限目录编译器 |
| 44 | 95 | A | S3 制品与 IAM 模块接口的兼容演进 |
| 45 | 95 | A | Partial S3 backend 迁移与跨 state 发布合同 |
| 46 | 95 | A | Saved plan 语义稳定发布、refresh-only 与 S3 漂移恢复 |
| 47 | 95 | A | 双区域 Provider 路由、AMI/Subnet 查询与 EC2/IAM 交付 |
| 48 | 95 | A | 双 S3 state 制品与 IAM 消费合同 |
| 49 | 95 | A | 双区域 EC2/LT/IAM 发布目录与受控替换 |
| 50 | 95 | A | 三 S3 state 的 S3/IAM/EC2 合同组合 Capstone |
| 51 | 95 | A | Declarative import、`moved` 与既有 EC2/IAM 模块化接管 |
| 52 | 95 | A | 外置网络上的 SG rule 地址迁移、重排与漂移修复 |
| 53 | 95 | A | 双区域 Provider alias、Launch Template/IAM 模块重构 |
| 54 | 95 | A | Sensitive JSON IAM policy 编译、会话身份与 plan/state 审计 |
| 55 | 95 | A | LocalStack 可执行的 EC2 rolling fleet、扩缩容与版本漂移 |
| 56 | 95 | A | `random_integer` 稳定分片与不可扰动 EC2 canary 发布 |
| 57 | 95 | A | Provider/模块版本约束、lockfile 升级与双区域 S3 路由 |
| 58 | 95 | A | 既有 IAM role/policy/attachment 的声明式导入与地址重构 |
| 59 | 95 | A | S3 remote-state 制品合同到 EC2 Launch Template 的版本传播 |
| 60 | 95 | A | 三 state、双区域、S3/IAM/EC2 灾备发布 Capstone |

## 统一完成合同

- 只修改每题的 `starter/`；fixtures、canonical tests 和 grader 是评分合同。
- 使用 Terraform `~> 1.6`，最终验证 CLI 为 Terraform 1.6.6。
- Canonical tests 不使用 `mock_provider` 或 `override_*`；AWS data source 连接真实 LocalStack。
- Grader 在读取候选目录前拒绝非 loopback、非 root-origin 或没有显式端口的 endpoint。
- Full E2E 在系统临时目录执行 saved plan、apply、clean plan、输入重排、真实漂移修复和 destroy。
- 最终交付只保留未完成 starter，不包含 answer、`.terraform`、state、plan、lockfile 或其他运行产物。

完成任一题后，在仓库根目录执行题目 Readme 中给出的 `tests/grade.ps1` 命令验收。

整套题目的结构、考纲类型白名单、评分元数据、starter 状态、canonical tests、grader 安全边界、
fixture JSON、Terraform 格式与运行产物，可在仓库根目录统一审计：

```powershell
$env:PATH = "$env:TEMP\tfpro-terraform-1.6.6;$env:PATH"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./new-challenges-2/audit.ps1
```
