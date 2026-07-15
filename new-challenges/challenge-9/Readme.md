# Challenge 9：同一 State 下的接管、迁移与漂移恢复

## 场景

团队把一个旧版服务目录交给你维护。旧配置使用 `count` 和旧资源名，另有一个
“guardian” 控制对象已经存在但尚未纳入当前配置。一个已退役对象必须从 Terraform
管理范围移除，但不能执行销毁。迁移完成后，运维人员还会手工篡改生成的 manifest，
你需要识别并恢复漂移。

整个练习必须复用**同一份 state**。复制一份新 state、销毁重建或直接编辑 state JSON
都不算完成。

## 官方大纲 Objective

- 1a：初始化 Terraform working directory。
- 1b：生成普通 plan，阅读地址迁移、import 与 drift 差异。
- 1c：apply 配置并验证幂等。
- 1d：理解受保护资源的销毁边界。
- 1e：使用 `state list/show/rm`、配置驱动 import 与 moved block 操作 state。
- 2d：正确使用 `for_each`、lifecycle 与稳定资源身份。

## 任务

1. 在临时目录应用 `fixtures/legacy`，建立旧版 state；后续所有步骤都在该目录完成。
2. 将 `terraform_data.workload[0..2]` 无替换迁移到以服务名为 key 的
   `terraform_data.service["..."]`。
3. 将 `local_file.inventory` 无替换迁移到 `local_file.manifest`。
4. 将 `starter/` 中 guardian 的资源定义和 import block 带入当前临时工作目录，后续仍在该目录中操作。
   使用 Terraform 1.6 import block，把 ID 为 `ops-guardian-v1` 的 guardian 接管到
   `terraform_data.guardian`；不能用普通 create 冒充 import。

> [!NOTE]
> `terraform_data` 是 Terraform 内置的 state 资源，不创建或查询云端对象，因此其 import ID 可以由配置指定。本题必须使用题目要求的 `ops-guardian-v1`，不能据此推断 AWS 等云资源也可以随意填写 ID；云资源必须先真实存在，再使用对应的真实资源 ID 导入。
5. 使用 `terraform state rm terraform_data.retired` 停止管理退役对象。不要 destroy。
6. 为 guardian 添加销毁保护：在 `terraform_data.guardian` 中使用
   `lifecycle { prevent_destroy = true }`；为 manifest 保持安全替换策略：在
   `local_file.manifest` 中使用 `lifecycle { create_before_destroy = true }`。
7. 迁移后确认 plan 幂等；再运行漂移脚本，观察 plan，apply 恢复文件内容，最后再次
   得到零变更 plan。

`starter/` 中保留了不稳定的数字 key、缺失的 import/moved/lifecycle 等 TODO。你可以
修改其中任意 `.tf`，但不要修改 `tests/` 或 legacy fixture。

> 版本边界：Terraform 1.6 尚不能使用声明式 `removed` block。本题要求的 1.6 做法是
> `terraform state rm`。`fixtures/removed-block.tf.example` 仅用于辨认后续版本的等价
> 能力，不得复制进答案。

## 验收命令

在本题目录运行参考流程或你自己的目录：

```powershell
pwsh ./tests/grade.ps1 -CandidateDir ./starter
```

只检查纯配置合同（不会复用 legacy state）：

```powershell
Set-Location starter
terraform init
New-Item -ItemType Directory -Force tests | Out-Null
Copy-Item ../tests/*.tftest.hcl tests/
terraform test
```

## 最终不变量

- state 只包含 `terraform_data.service["api|web|worker"]`、guardian 和 manifest。
- 旧 workload 地址及 retired 地址均不存在。
- 迁移计划没有 delete/create 资源替换。
- guardian 的 state ID 是 `ops-guardian-v1`，且配置有 `prevent_destroy`。
- manifest 漂移可被 plan 发现，apply 后内容和 checksum 恢复。
- 最终 `terraform plan -detailed-exitcode` 返回 0。

## 安全边界

- 本题仅使用内建 `terraform_data` 与本地 `local_file`，不访问云账号。
- grader 只删除本题下的 `.grade-work`，不会操作仓库外文件。
- 不允许 `terraform state push`、手改 state JSON、`-target` apply 或 destroy 退役对象。
- `prevent_destroy` 不是远端删除保护；它只约束包含该 lifecycle 的 Terraform 计划。

## 官方参考

- https://developer.hashicorp.com/terraform/language/import
- https://developer.hashicorp.com/terraform/language/modules/develop/refactoring
- https://developer.hashicorp.com/terraform/cli/commands/state/rm
- https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle
