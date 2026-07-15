# Challenge 36：S3 制品清单与可复现发布

**难度：94 / 100**  
**考试模式建议时间：60 分钟；首次学习建议时间：100 分钟**

发布平台收到一份弱类型 JSON manifest。你要把它编译成稳定、可审计的 S3 制品发布图，并证明 saved plan、远端漂移恢复和输入重排不会破坏发布身份。

完成 `starter/`：

1. 读取并规范化 `manifest_path`；只发布 `enabled=true` 的条目。
2. 分别拒绝重复 `artifact_id`、重复 `object_key`、非法布尔值、空字段、目录穿越、零行 manifest 和 enabled 条目引用的不存在本地制品；disabled 条目不进入发布图。
3. 创建一个 `aws_s3_bucket.release`，并用 `artifact_id` 作为 `aws_s3_object.artifact` 的稳定 `for_each` key。
4. 每个对象必须设置 `source`、`source_hash`、`etag`、`content_type`，以及 ReleaseId/ArtifactId/Owner/RunId metadata 和 tags。
5. 输出排序后的制品 ID、对象地址、key/checksum/content-type 发布合同和 LocalStack caller account。
6. 所有 AWS 资源带 `RunId = var.run_id`；provider 只能使用字面量 `test/test` 与 loopback LocalStack 的 `s3`、`sts` endpoints。

Canonical tests 精确包含 12 个 run。真实 grader 会审计 saved plan JSON，改变当前变量后应用已保存计划，回读 S3 bytes、metadata、content type 与 tags，验证 manifest 重排为零变更，制造一个对象的远端内容漂移并恢复，最后 destroy 并确认零残留。

```powershell
pwsh ./tests/grade.ps1
```

fixtures 是只读输入合同；不要修改它们，也不要接触真实 AWS。
