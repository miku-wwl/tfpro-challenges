# Challenge 9–40：B 级题目整改验证报告

验证日期：2026-07-15

本轮按上一轮评级，只整改 Challenge 9–40 中仍为 B 的 17 道题。此前已经整改为 A 的题目不重复改动。
最终 17 道题全部达到 **A**，平均难度 **95.8 / 100**。

## 最终评级

| Challenge | 最终评级 | 难度 | Canonical runs | 完整 E2E 核心验证 |
|---|---:|---:|---:|---|
| 11 | A | 95 | 5/5 | 双区域 alias、caller identity、真实 bucket 路由、saved plan、零残留 |
| 12 | A | 96 | 5/5 | local→S3 backend 迁移、跨 state 合同、版本升级、逆序销毁 |
| 15 | A | 95 | 6/6 | 外置 VPC/subnet、真实 subnet data、稳定规则地址、删除漂移修复 |
| 16 | A | 95 | 7/7 | saved plan、state pull、refresh-only、真实 S3 漂移精确修复 |
| 18 | A | 97 | 9/9 | 双 S3 state、双区域 provider 分支、重排、漂移、逆序销毁 |
| 21 | A | 96 | 10/10 | 外置网络、CSV ingress graph、saved plan、真实规则漂移修复 |
| 22 | A | 96 | 9/9 | partial S3 backend、迁移、remote-state 合同、v2 发布、逆序销毁 |
| 25 | A | 96 | 8/8 | declarative import、版本化对象、revision pointer、替换与恢复 |
| 26 | A | 95 | 8/8 | IAM role/policy/attachment、policy document、真实 attachment 漂移 |
| 28 | A | 97 | 8/8 | 双 S3 state、双 provider、版本传播、重排与逆序销毁 |
| 29 | A | 96 | 8/8 | 双区域嵌套模块、S3/IAM 合同、漂移与零残留 |
| 30 | A | 96 | 8/8 | foundation/platform/workloads 三个真实 S3 state 与跨 state 合同 |
| 31 | A | 95 | 10/10 | CSV、真实 AMI/subnet data、SG/LT/EC2、重排与实例 tag 漂移 |
| 33 | A | 95 | 8/8 | dev/stage/prod 三套 partial S3 backend、saved-plan 隔离与漂移边界 |
| 35 | A | 96 | 12/12 | 双 state、双区域外置网络、IAM/SG/LT/EC2、重排与漂移 |
| 37 | A | 95 | 12/12 | 官方 SG/ingress-rule graph、输入合同、重排与真实规则删除修复 |
| 40 | A | 97 | 18/18 | 双 state 制品发布、v1→v2 精确 action map、双实例 rollover、逆序销毁 |

合计：**151/151 canonical runs**，并且每道题都完成了一次或多次真实 LocalStack Full E2E，最终退出码均为 0。

## 统一验收门槛

- 使用官方 Terraform **1.6.6**；测试配置不使用 `mock_provider` 或任何 `override_*`。
- 候选目录只允许 Terraform HCL，不依赖候选脚本、手工 state 命令或隐藏答案。
- AWS 请求只允许显式 loopback LocalStack endpoint 和 `test/test` 凭据；不安全 endpoint 在候选路径解析前即被拒绝。
- Full E2E 覆盖 saved plan JSON 审计、真实 apply、clean plan、输入重排、带外漂移、精确修复、saved destroy/逆序销毁及题目命名空间零残留。
- 全部 fixture JSON 可解析，全部 `grade.ps1` 通过 Windows PowerShell 5 AST 且为 ASCII，Terraform recursive fmt 与 `git diff --check` 通过。
- 临时参考实现均已删除；17 个 `starter/` 均保留未完成状态，执行 `-UnitOnly` 全部以非零状态拒绝。
- `.terraform`、lockfile、state、plan、backup、lock-info 和 crash log 等运行产物均未留在题目目录。

题目资源类型与工作流以 HashiCorp 公布的 Terraform Authoring & Operations Professional
[考试复习清单](https://developer.hashicorp.com/terraform/tutorials/pro-cert/pro-review)为边界；LocalStack 只承担本地 AWS 行为验证。

## 环境清理说明

本轮 grader 创建的 S3、DynamoDB、SNS、IAM 与 EC2 命名空间资源均已清空。LocalStack 中原先存在的
`Security`、`DevOps` 实例、`challenge2-ami` 和旧 launch template 不属于本轮测试，已原样保留。
