# Challenge 16：Terraform CLI 自动化与故障恢复

难度：**91 / 100**　建议用时：**90 分钟**

## 场景

发布流水线要管理一份本地 service inventory。旧脚本直接 `apply -auto-approve`，既没有保存/审计 plan，也把 `-detailed-exitcode` 的 `2` 当成错误；值班手册还在 state 损坏时建议重新 apply。你要实现可审计、可恢复、可重复运行的 PowerShell 工作流。

本题只创建临时目录中的 `terraform_data`、`local_file` 和 local state，不使用云 provider。

## 开始

```powershell
cd tmp2/challenge-16/starter
terraform init
pwsh ../tests/grade.ps1 -Root .
```

只修改 `starter/`。grader 会把候选目录和 fixtures 复制到 OS 临时目录，所有 state 操作都发生在副本中。

## 任务

1. 把 catalog 转换为按 service name 建 key 的 map；停用 service 不进入资源图，CSV/JSON 顺序变化不改变地址。
2. 完成 environment validation，并输出排序后的 service name 与完整资源地址。
3. 完成 `scripts/operate.ps1`：
   - `terraform init -input=false`；
   - `plan -detailed-exitcode -out=...`，正确区分 `0`（无变化）、`1`（错误）、`2`（有变化）；
   - `terraform show -json` 审计 saved plan，拒绝首次 plan 中的 delete；
   - 只 apply 已审计的 saved plan，随后证明 clean plan 返回 `0`；
   - `terraform state pull` 创建显式备份，模拟 `state rm` 后用 `state push -force` 恢复，并证明地址恢复；
   - 外部修改 inventory 文件，使用 `plan/apply -refresh-only` 记录 drift，再生成、审计并应用 repair saved plan；
   - 写入 `.automation/evidence.json`，字段合同见 grader 错误信息。
4. 所有外部命令都检查 exit code；脚本中不得删除调用方传入的 workspace。

## `-detailed-exitcode` 合同

| Exit code | 含义 | 自动化动作 |
|---:|---|---|
| 0 | plan 无变化 | 成功，无需 apply |
| 1 | Terraform 错误 | 立即失败 |
| 2 | plan 有变化 | 审计 JSON 后才可 apply |

## 验收

```powershell
terraform fmt -check -recursive .
terraform validate
pwsh ../tests/grade.ps1 -Root .
```

`grade.ps1` 会实际走完 saved plan、JSON audit、state backup/restore、refresh-only 与 repair 流程。

## 不变量

- 只有被审计的 `.tfplan` 可以进入 apply。
- state backup 必须在破坏性 state 子命令之前落盘且非空。
- `refresh-only` 只记录现实，不应暗中修改配置。
- state 恢复后 service 地址集合与恢复前一致；最终普通 plan exit code 为 `0`。

## 安全边界

- grader 只使用自己创建并验证过路径的临时目录，结束后清理该目录。
- 不使用真实 backend、不运行 `state push` 到远程 workspace。
- 不把 `.tfstate`、plan JSON、plan binary 或生成 inventory 提交到版本库。

## Terraform Professional objective

覆盖 Professional 大纲中的 CLI automation、saved plan contract、machine-readable JSON、drift/refresh-only、state inspection/backup/recovery、资源身份稳定性，以及自动化失败语义。
