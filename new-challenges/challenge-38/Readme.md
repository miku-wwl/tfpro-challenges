# Challenge 38：AWS Provider 与 Module 供应链事故诊断

难度 **94/100**；考试模式建议 **60 分钟**，首次学习建议 **105 分钟**。

## 事故背景

一次 child module 升级后，流水线在不同机器上选择了不同 AWS provider；与此同时，DR 数据源悄悄走了默认区域。你需要修复 provider 约束交集、provider slot 映射和诊断合同，并用 lockfile、依赖图、schema、plan JSON 与真实 LocalStack 回读形成完整证据链。

## 任务

仅修改 `starter/`：

1. root 保持 `hashicorp/aws ~> 5.100`；child 使用 `>= 5.100, < 6.0` 并声明 `aws.dr`。
2. root 只有 default 与 `aws.dr` 两个安全 LocalStack provider，并显式传给 module；endpoint 变量自身必须拒绝非 loopback、路径、凭证、查询、fragment、缺失/越界端口。
3. child 分别查询 AMI、caller identity、session context，并各建一个区域 VPC。
4. 建立 region、AMI、account、issuer 四类不可绕过的 precondition；每一类都同时覆盖 primary 与 dr，不能用一个 catch-all 配三个平凡条件。
5. 输出诊断、VPC 和 supply-chain 合同。

运行：

```powershell
pwsh ./tests/grade.ps1
```

Canonical tests 精确包含 12 个 run。grader 会额外检查 lockfile、`terraform providers`、`terraform providers schema -json`、冲突约束 init 失败、plan JSON 的 8 个精确配置地址与 2 个 VPC create、真实双区域 VPC ID/CIDR，以及成功或失败路径上的零残留。
