# Challenge 25：声明式接管与版本化 S3 配置恢复

难度：**96 / 100**；考纲契合度：**A**；考试模式 **80 分钟**，首次完整学习 **130 分钟**。

一个配置 bucket 已由平台预先创建，但尚未进入当前 state。你需要用 Terraform 1.6 declarative import 接管它，并同时维护一个稳定的 `current` 对象与一个按版本和摘要命名的 immutable revision 对象。配置升级必须显式替换 current；带外篡改必须经过 refresh-only 记录，再由 saved repair plan 精确恢复。

只修改 `starter/` 中的 Terraform HCL；禁止候选脚本、`terraform state rm/mv/push` 和手工 `terraform import`。

## Terraform 任务

1. 将 endpoint 限制为带显式合法端口的 loopback root origin；provider 使用字面量 `test/test`、S3 path-style、S3/STS endpoints 和三项 skip flags。
2. 用 `jsondecode(file(...))` 读取配置，再用 `jsonencode` 生成 canonical JSON 与 SHA-256。
3. 验证 environment、正整数版本，以及 JSON 中 application/environment/features 合同。
4. 用静态 `import` block 把预存 bucket 接管到 `aws_s3_bucket.config`；不得重建。
5. 只使用公开清单中的 `aws_s3_bucket` 和 `aws_s3_object`：
   - 一个稳定的 `config/current.json`；
   - 一个以 `v<version>-<sha256>` 为稳定 key 的 immutable revision；
   - 一个稳定的 `config/revision.json` revision pointer。
6. 三类对象都设置声明式 content、content type、`etag = md5(...)`、`source_hash` 和审计 tags。
7. revision pointer 随版本更新，current 使用 `replace_triggered_by = [aws_s3_object.revision_pointer]`；加入独立 preconditions 与 content-type postcondition。
8. 输出 revision identity、确定性 bucket 名和 object keys，禁止输出配置正文。
9. v2 saved plan 必须只更新 revision pointer、轮换 revision 并替换 current；refresh-only 只记录 current 漂移；repair plan 只能修改 current。
10. saved destroy 后 bucket 与对象必须零残留。

本题已移除 DynamoDB、`terraform_data`、`prevent_destroy` 和手工 state 清理。考点直接对应 import、lifecycle、plan/apply、drift 和公开 S3 资源。

## 验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 使用 Terraform **1.6.6** 和真实 LocalStack 执行 **8 个无 mock/override 的普通 plan tests**，随后验证 declarative import、v2 replacement、refresh-only、精确 repair、clean plan 与 saved destroy。

仅运行 canonical 测试（仍会在 LocalStack 创建并清理一个临时待导入 bucket）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```

## 考纲映射

- **1b / 1c / 1d / 1e**：saved plans、declarative import、refresh-only、drift repair 与 destroy；
- **2a / 2c / 2d / 2e**：pre/postconditions、JSON functions、`for_each` 与 lifecycle；
- **3c**：非交互式 plan JSON 审计和 apply 同一 saved plan。
