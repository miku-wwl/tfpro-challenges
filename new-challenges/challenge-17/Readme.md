# Challenge 17：双区域嵌套模块与 Provider Graph 排障

难度：**94 / 100**　建议用时：**90 分钟**

## 场景

一个日志平台从根模块重构为 `platform -> regional-stack` 两层模块。primary 与 DR 必须落在不同 AWS region；一次错误重构却把两个实例都路由到了 primary provider，DR output 也错误引用 primary。你需要修复 provider graph、模块依赖与 state 地址迁移声明。

provider 使用固定 `test/test` 并把 S3、SNS、STS 路由到本机 LocalStack。canonical tests
仍使用两个 AWS mock provider隔离验证 provider graph。

## 开始

```powershell
cd tmp2/challenge-17/starter
terraform init
pwsh ../tests/grade.ps1 -Root .
```

只修改 `starter/`；`fixtures/legacy-addresses.txt` 记录重构前 state 地址。

## 任务

1. 根模块保留 `aws.primary` 与 `aws.dr`，不得创建隐式 default provider。将两个 alias 显式传入 `module.platform`。
2. `modules/platform` 用 `configuration_aliases` 声明它接收的两个 provider，并将正确 provider 映射到两个嵌套 `regional-stack` 实例。
3. DR stack 必须消费 primary 的 `topic_arn`，并用显式 `depends_on` 表达平台的顺序策略；解释它与 output 引用形成的隐式依赖为何可以并存。
4. 修复 root/platform outputs，确保 primary 与 DR inventory 没有交叉引用。
5. 根据 fixture 添加 `moved` blocks，把四个 legacy root 地址迁移到嵌套模块地址。不得通过 `state rm`/重新创建完成重构。
6. validation 必须拒绝相同的 primary/DR region，以及不符合 S3 命名规则的 prefix。
7. HCL 只能使用固定 LocalStack `test/test`，不得写真实 access key、secret、profile
   或 assume-role 凭证。

## 目标 provider graph

```text
aws.primary -> module.platform/aws.primary -> module.primary/aws.workload
aws.dr      -> module.platform/aws.dr      -> module.dr/aws.workload
module.primary.topic_arn ------------------> module.dr.peer_topic_arn
```

## 验收

```powershell
terraform fmt -check -recursive .
terraform validate
pwsh ../tests/grade.ps1 -Root .
```

测试给两个 alias 返回不同的 `aws_region`，因此“配置能 plan”不代表路由正确；只有 DR 真正使用 `aws.dr` 才能通过。

## 不变量

- module 内不配置 region；region 由调用方 provider 决定。
- provider configuration 只存在于 root，child module 只声明 requirement/alias contract。
- 四个 legacy 地址均有确定的 moved 目标。
- 跨模块依赖通过 output，而不是直接引用 child module 内资源。

## 安全边界

- 可在 LocalStack 执行 apply/destroy；禁止把 endpoint 改向真实账户。
- bucket 名为测试数据，不代表真实全局唯一名称。
- 不创建 IAM user/access key，不接触本机共享 credentials 文件；`test/test` 只是模拟值。

## Terraform Professional objective

覆盖 Professional 大纲中的多 provider 配置、module provider inheritance/alias 映射、嵌套 module contract、dependency graph、output 封装、state-preserving refactor、输入 validation 与 provider troubleshooting。
