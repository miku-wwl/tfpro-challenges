# Challenge 32：敏感启动数据与身份边界审计

**难度：95 / 100（Terraform Professional = 100）**  
**建议时间：115 分钟**

安全团队要求你为 EC2 workload 建立启动数据和身份边界。难点不是简单加一个 `sensitive = true`，而是理解敏感值在 human plan、saved plan JSON、state 和 output 中分别如何表现。

完成 `starter/`：

1. `bootstrap` 必须是带 `sensitive = true` 的复杂对象，包含 API token、数据库密码和 feature flag map，并校验最小长度。
2. 用 `templatefile` 渲染 `fixtures/bootstrap.sh.tftpl`，再把 base64 结果写入 `aws_launch_template.identity.user_data`。
3. 用两个 `aws_iam_policy_document` 分别生成 EC2 trust policy 与权限 policy；权限只允许读取显式 SSM parameter ARNs，禁止 wildcard action/resource。
4. 创建 IAM role、managed policy、attachment、instance profile 和 launch template，正确连接身份链。
5. 输出只能包含 `bootstrap_digest`、`identity_contract` 和 `launch_template_id`；digest 必须是渲染结果的 SHA-256，不能输出明文或 base64 payload。
6. 所有可标记的 AWS 资源都必须携带 `RunId = var.run_id`。
7. human plan 中 token/password 必须显示为敏感值而不是明文；同时你必须接受 plan JSON 与 state 会持有 `user_data`，因此它们本身属于敏感制品。
8. grader 会生成并审计 saved plan，然后修改磁盘上的变量再应用原 plan，以证明 apply 的是被审阅快照。

LocalStack 会把 launch template 的顶层 tags 回读成额外的 `launch-template` tag specification；请用只针对 `tag_specifications` 的 lifecycle 忽略模拟器噪声，不得扩大到整个资源。

Canonical tests 精确包含 8 个 run，独立覆盖 wildcard、空 boundary、tfpro namespace 外 ARN 与非 loopback endpoint。`expected-boundary.json` 是 action/namespace 的可执行合同。真实 E2E 会创建 IAM role/policy/profile 和 EC2 launch template，检查 STS 测试账号、plan/state sensitivity metadata、远端启动数据、clean plan、destroy 与零残留。

```powershell
pwsh ./tmp2/challenge-32/tests/grade.ps1
```

human plan 的 redaction 只是显示层保护；不得把 `.tfplan`、plan JSON 或 state 当作无敏感信息的普通日志。fixtures 是只读合同，禁止使用真实 AWS。
