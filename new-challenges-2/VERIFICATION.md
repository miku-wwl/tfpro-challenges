# Challenge 41–60 验证报告

验证日期：2026-07-16

最终结论：Challenge 41–60 共 20 题全部达到 **95 / 100**、考纲契合度 **A**。每题都先用临时参考实现完成 Terraform **1.6.6** + Docker LocalStack 的 Unit 与 Full E2E，再恢复为未完成 starter；临时参考实现已全部删除。

## 逐题证据

| Challenge | 难度 | 契合度 | Canonical runs | Full E2E 核心验证 |
|---|---:|---:|---:|---|
| 41 | 95 | A | 7/7 | 同一 state lineage 的 6 地址 `moved` 零动作迁移、重排、对象漂移修复、saved destroy |
| 42 | 95 | A | 7/7 | 三 provider slot 路由、真实 region/identity 回读、IAM 漂移修复、零残留 |
| 43 | 95 | A | 21/21 | IAM JSON 编译器、trust/policy document、单 policy 升级、attachment 漂移修复 |
| 44 | 95 | A | 9/9 | 模块接口 V1→V2 的 4 个精确更新、稳定 ID、重排、attachment 修复 |
| 45 | 95 | A | 7/7 | local→partial S3 backend 迁移、真实 remote-state V2 传播、逆序销毁 |
| 46 | 95 | A | 8/8 | saved-plan 语义、refresh-only、S3 漂移发现与精确恢复 |
| 47 | 95 | A | 8/8 | 双区域 provider、真实 AMI/subnet data、EC2/IAM 路由与漂移重建 |
| 48 | 95 | A | 15/15 | 双 S3 state 合同、IAM 消费、stale 拒绝、S3/IAM 漂移和逆序销毁 |
| 49 | 95 | A | 10/10 | 双区域 EC2/LT 发布、受控替换、扩容与 saved destroy |
| 50 | 95 | A | 19/19 | 三个 S3 state 的 S3/IAM/EC2 合同链、指纹、V2 rollout、逆序销毁 |
| 51 | 95 | A | 6/6 | EC2/IAM declarative import + `moved` 双路径接管、零远端变更、漂移修复 |
| 52 | 95 | A | 7/7 | 4 条 SG rule 地址迁移、CSV 重排稳定、真实规则删除与单地址修复 |
| 53 | 95 | A | 7/7 | 双区域 provider alias、6 地址模块迁移、DR SG 漂移与双区清理 |
| 54 | 95 | A | 8/8 | sensitive policy 编译、caller/session context、plan/state 防泄漏、attachment 修复 |
| 55 | 95 | A | 8/8 | LocalStack Community 可执行的 EC2 rolling fleet、扩缩容、版本替换与漂移 |
| 56 | 95 | A | 13/13 | `random_integer` 稳定 canary 分片、单 fleet 受控替换、真实 EC2 漂移修复 |
| 57 | 95 | A | 13/13 | stale lock 拒绝、AWS provider 5.100.0 升级、双区 module routing 与漂移 |
| 58 | 95 | A | 11/11 | IAM role/policy/attachment 的 declarative import、地址重构、升级与脱附修复 |
| 59 | 95 | A | 20/20 | 双 S3 state、缺字段/伪指纹篡改拒绝、真实 EC2 UserData、V2 精确替换与严格清理 |
| 60 | 95 | A | 16/16 | 三 state 双区域 DR、primary→DR→recovery、active exact-one、两层 lineage 与逆序销毁 |

合计：**220/220 canonical runs**；**20/20 Full E2E** 退出码为 0。

## 统一验收门槛

- 所有普通测试均为真实 `terraform test` run；没有 `mock_provider`、`override_*` 或候选脚本。
- AWS provider 使用字面量 `test/test`、三项 skip flags 和显式 loopback LocalStack endpoints；20/20 grader 均在解析候选目录前拒绝非 loopback endpoint。
- Full E2E 覆盖 saved-plan JSON action map、真实 apply/clean plan、输入重排、带外漂移、精确修复、saved destroy 和 run-scoped API 零残留。
- 资源与 data source 以 HashiCorp 当前 [Terraform Professional exam content list](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review) 为边界。LocalStack Community 需要许可证的 Auto Scaling API 不作为运行时依赖；相关发布题使用清单内的 EC2 与 Launch Template 语义。
- 20 个 grader 均固定 Terraform 1.6.6，通过 Windows PowerShell 5 AST，保持 ASCII-only；所有 JSON fixture 可解析，Terraform recursive fmt 通过。
- 20/20 默认 `grade.ps1 -UnitOnly` 会因 starter 的实质未完成合同以非零退出，而不是因路径解析失败；每题只保留 HCL starter。
- 最终目录不含 `answer/`、`.terraform/`、lockfile、state、plan、backup、lock-info 或 crash log。

## 可重复审计

在仓库根目录执行：

```powershell
$env:PATH = "$env:TEMP\tfpro-terraform-1.6.6;$env:PATH"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./new-challenges-2/audit.ps1
```

最终审计结果：`20 challenges`、`220 canonical runs`、`0 failures`。
