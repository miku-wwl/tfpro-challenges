# Challenge 16：Saved Plan、Refresh-only 与真实 S3 漂移恢复

难度：**95 / 100**；考纲契合度：**A**；考试模式 **75 分钟**，首次完整学习 **120 分钟**。

JSON service catalog 要发布为一个真实 S3 inventory。候选人只修改 `starter/` Terraform HCL；saved
plan、exit code、state inspection、refresh-only 和 drift 注入全部由 grader 驱动，不要求编写 PowerShell，
也不允许 `state push/rm` 之类破坏性恢复。

## Terraform 任务

1. `jsondecode(file(...))` 后规范化 service，独立拒绝空 catalog、重复 name、非法字段和无 enabled service。
2. enabled service 以 name 作为稳定 `for_each` key；输入数组重排不得改变地址或 canonical SHA-256。
3. 创建一个 `aws_s3_bucket.inventory`、每服务一个 `aws_s3_object.service` 和一个 canonical index object。
4. service object 设置 JSON content、`etag = md5(...)`、metadata 与 tags，确保内容/标签漂移可被刷新和修复。
5. 输出排序 names、bucket/index、canonical SHA-256 和精确 managed address contract。
6. AWS provider 只使用字面量 `test/test`、S3/STS loopback endpoint、path-style 和三项 skip flags。

## 验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 执行 **7 个 Terraform 1.6.6 普通 plan tests**（无 mock/override），再真实执行：初始 saved plan
JSON 审计与同文件 apply、clean/reorder exit code 0、`state pull` 只读备份、AWS CLI 篡改对象正文与 tags、
saved refresh-only plan/apply、只更新一个对象的 saved repair plan、clean plan、saved destroy 和零残留。

## 考纲映射

- **1b–1e**：saved plan/apply/destroy、state inspection、refresh-only 与 drift reconciliation；
- **2a / 2c / 2d / 2e**：checks、JSON/HCL 函数、稳定 `for_each`、复杂 outputs；
- **3c**：自动化中的 detailed exit code、plan JSON 和 immutable saved plan；
- **5b / 5c / 5d**：AWS provider、测试凭证与 endpoint 排障。

Candidate workload 只使用公开考试资源清单中的 `aws_s3_bucket` 和 `aws_s3_object`。
