# Challenge 51：Declarative Import 与 Moved 双路径零替换接管

难度：**95 / 100**；考试模式 **80 分钟**，首次完整学习 **140 分钟**。评级：**A**。

一套既有 IAM role、instance profile 和 EC2 instance 已在 LocalStack 中运行。新配置必须把它们纳入一个
child module：空 state 使用 Terraform 1.6 declarative `import`；已有 legacy state 使用 `moved` blocks。
两条接管路径都不能 create、delete、update 或 replace 真实资源，也不能依赖候选脚本、`terraform state mv`
或 mock/override。

只修改 `starter/`：

1. 严格解析 `fixtures/takeover.json`，独立阻断顶层/workload schema、contract version、name 与 instance type。
2. 通过 grader 外建 subnet 和真实 AMI data source 读取网络/镜像，禁止管理 VPC/subnet。
3. child module 管理精确的 `aws_iam_role.this`、`aws_iam_instance_profile.this`、`aws_instance.this`，保持既有名称、AMI、subnet、profile 与五项标签合同。
4. 三个 declarative `import` blocks 必须直接指向最终 module 地址；ID/name 来自显式变量。
5. 三个 `moved` blocks 必须把 `aws_iam_role.legacy`、`aws_iam_instance_profile.legacy`、`aws_instance.legacy` 映射到相同最终地址；禁止 state CLI 迁移。
6. 输出 catalog、最终地址、资源 ID/name、subnet/AMI 与 ownership 合同；JSON key 重排必须零变化。
7. provider 只允许 loopback root-origin LocalStack `ec2,iam,sts` endpoint、字面量 `test/test` 和三项 skip flags。
8. grader 使用 Terraform 1.6.6 运行 6 个普通 plan tests；Full 先 apply legacy fixture，再审计 moved saved-plan 的三个 `previous_address` 与零动作；随后用空 state 实际 apply 三个 declarative imports，验证 clean、真实 tag drift、destroy 与零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```
