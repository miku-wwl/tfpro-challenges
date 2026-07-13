# Challenge 20：双区域嵌套模块与零替换重构

**难度：96 / 100（Terraform Professional = 100）**  
**建议时间：105 分钟**

现有 state 在 root module 中管理两个区域的 S3 bucket 与 SNS topic。你需要把它们重构为两层模块：root → `regional_stack` → `storage`，同时保持资源远端身份不变。

完成 `starter/`：

1. root 必须配置 `aws.primary` 与 `aws.dr`，固定使用 LocalStack 的 `test/test`，并为 S3、SNS、STS 声明 endpoint。
2. `module.primary` 使用 `aws.primary`；`module.dr` 使用 `aws.dr`。
3. `regional_stack` 与嵌套 `storage` module 都必须以 `configuration_aliases` 声明 `aws.target`，并逐层显式传递 provider。
4. 为四个 legacy root 地址编写 `moved` blocks，使其迁移至最终嵌套地址；迁移 plan 不允许 create、delete 或 replace。
5. 输出稳定的 `regional_contract` 与 `failover_contract`。primary 与 DR 应互相指向对方 bucket，区域、bucket、topic ARN 必须正确。
6. 重构 apply 后必须 clean，destroy 后不得留下本题 bucket 或 topic。

grader 会先用 fixture 创建旧 state，再在原 state 上换入你的代码，因此只写“看起来正确”的新模块还不够；state 地址和 provider 绑定都必须正确。

```powershell
pwsh ./tmp2/challenge-20/tests/grade.ps1
```

不要使用真实 AWS 账号、凭证或非 loopback endpoint。

