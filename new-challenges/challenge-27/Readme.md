# Challenge 27：可审计的 S3/SNS 发布与恢复流水线

难度：**97/100**，建议限时 135 分钟。

本题不是只写几个资源：你要交付一条可复跑、可审计、有恢复证据的发布流水线。Terraform 将 release manifest 写入 S3，并把 `releases/` 下的 ObjectCreated 事件发送到 SNS。所有 API 只使用本机 LocalStack。

## Terraform 任务

1. 固定 LocalStack `test/test` 凭证；S3、SNS、STS endpoint 必须来自通过 loopback 验证的变量，S3 使用 path-style。
2. 严格验证 SemVer `release_version`：允许 prerelease/build metadata，但 core 与纯数字 prerelease identifier 禁止前导零；解析 manifest，并检查其中 application/environment/version 与变量一致。
3. 创建唯一 S3 bucket、SNS topic、允许该 bucket 发布的 topic policy、S3 bucket notification，以及 `releases/<version>/manifest.json` 对象。
4. notification 只能监听 `s3:ObjectCreated:*` 且限定 `releases/` prefix，并显式等待 topic policy。
5. 输出 release identity、bucket、object key、topic ARN 和稳定资源地址，不得输出 manifest 正文。

## 自动化任务

完成 `scripts/` 中三个 runbook：

- `publish.ps1`：保存 plan；用 `terraform show -json` 拒绝非 allowlist resource type 与未批准 delete。版本升级时，只允许同一 bucket 内 `aws_s3_object.manifest` 从旧确定性 release key replacement 到当前版本 key；其他 delete 一律拒绝。只 apply 已审计的 saved plan；正确解释 `-detailed-exitcode`；按版本写 evidence。
- `state-drill.ps1`：`state pull` 备份，模拟丢失一个 binding，再用 `state push -force` 恢复；恢复后 clean plan；写备份哈希证据。
- `recovery-drill.ps1`：制造 S3 对象带外漂移；保存并审计 refresh-only plan，apply 它以记录漂移；生成普通 repair plan 恢复声明内容；最终 clean plan。同时执行一个预期失败的发布 plan，证明失败前后 state 哈希相同并写 rollback evidence。

运行：

```powershell
pwsh ./tests/grade.ps1
```

grader 使用唯一命名，执行 5 个 canonical mock tests，并在 LocalStack 上真实跑发布、state restore、refresh-only/repair、预期失败及 destroy。临时 plan、state 与 evidence 只存在隔离工作目录，结束后自动清理。不要修改 fixtures 或 tests。
