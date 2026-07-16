# Challenge 66：Destroy Plan、定向退休与配置意图恢复

## 题目目标

你接手了一个同时保存当前版和旧版制品的 S3 bucket。先审阅完整销毁计划但不得执行，
再只退休旧对象，最后让 Terraform 配置与实际退休意图重新一致。重点是区分“查看销毁
影响”“例外情况下定向操作”和“恢复日常完整 plan”三个阶段。

考纲对应：资源生命周期、destroy plan、saved plan、资源地址、state 检查与安全销毁。

## 开始前检查

在 `new-challenges-3/challenge-66` 中执行：

```powershell
docker ps --filter 'name=localstack'
Invoke-RestMethod http://localhost:4566/_localstack/health
terraform version
```

本题只允许连接 `http://localhost:4566`。`test/test` 是 LocalStack 协议占位凭证，
不得替换为真实 AWS 凭证。`destroy-all.tfplan` 只能审阅，绝对不要 apply。

## Task 1：建立完整的初始 state

保持 `challenge-66.tf` 不变，初始化并创建 bucket、当前对象和旧对象：

```powershell
terraform fmt -check
terraform init
terraform validate
terraform plan '-out=initial.tfplan'
terraform apply initial.tfplan
terraform state list
```

预期普通 plan 为 `3 to add`。apply 后，三个 managed resource 地址都在 state 中：
`aws_s3_bucket.releases`、`aws_s3_object.active`、`aws_s3_object.retired`。

## Task 2：只审阅完整销毁计划

不要修改配置。生成并阅读 saved destroy plan：

```powershell
terraform plan -destroy '-out=destroy-all.tfplan'
terraform show -no-color destroy-all.tfplan
```

预期计划销毁三个 managed resources。确认 bucket 和当前对象也在影响范围内后停止，
不要运行 `terraform apply destroy-all.tfplan`。saved plan 固化了生成时的配置与 state，
不能把旧计划当作永久可复用的运维指令。

官网入口：[Create a destroy plan](https://developer.hashicorp.com/terraform/cli/commands/plan#planning-modes)。

## Task 3：定向退休旧对象

生产意图只是删除旧对象。先生成仅包含该地址的定向销毁计划，再应用同一个计划：

```powershell
terraform plan -destroy '-target=aws_s3_object.retired' '-out=retire.tfplan'
terraform show -no-color retire.tfplan
terraform apply retire.tfplan
terraform state list
```

PowerShell 中应把整个 `-target=...` 参数加引号。预期定向计划只有
`aws_s3_object.retired` 的一个 delete；bucket 和当前对象仍在 state。Terraform 会提示
resource targeting 警告，这是本题刻意模拟的例外操作，不代表日常工作流应依赖 `-target`。

官网入口：[Resource targeting](https://developer.hashicorp.com/terraform/cli/commands/plan#resource-targeting)。

## Task 4：恢复配置表达的真实意图

定向销毁后立刻运行完整 plan：

```powershell
terraform plan
```

预期 Terraform 计划重新创建旧对象，因为 `challenge-66.tf` 仍声明
`aws_s3_object.retired`。这不是漂移修复错误，而是配置仍表达“应该存在”。

现在编辑 `challenge-66.tf`，删除整个 `aws_s3_object.retired` resource block。不要删除
bucket 或当前对象，也不要用 `ignore_changes` 掩盖差异。然后执行：

```powershell
terraform fmt
terraform validate
terraform plan
```

预期得到 `No changes`。此时远端对象、state 和配置三者才共同表达“旧版本已退休”。

## Task 5：最终验收与清理

先确认普通 plan 干净，再清理剩余资源和运行产物：

```powershell
terraform plan
terraform destroy -auto-approve
terraform state list
Remove-Item .\initial.tfplan,.\destroy-all.tfplan,.\retire.tfplan -ErrorAction SilentlyContinue
```

最终 `terraform state list` 不应输出任何地址，LocalStack 中不应再有本题 bucket。

## Terraform 1.6 边界

- 本题固定使用 Terraform `~> 1.6.0`，不使用后续版本的 `removed` block。
- `-target` 用于异常恢复或题目明确要求的分阶段操作，不是常规依赖管理工具。
- saved plan 必须先审阅再 apply；配置或 state 变化后应重新生成，而不是继续使用旧文件。

## 最终检查

- 完整 destroy plan 从未被 apply。
- 定向计划只删除旧对象。
- 删除旧对象的配置声明后，完整 plan 为零变更。
- 最终 destroy 后 state 为空，三个 `.tfplan` 文件已删除。
