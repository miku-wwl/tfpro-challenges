# Challenge 27：可审计的 S3 制品发布与漂移修复

难度：**95 / 100**；考纲契合度：**A**；考试模式 **75 分钟**，首次完整学习 **120 分钟**。

一个应用的 release manifest 以 JSON 列表描述多个 S3 制品。你需要把它编译成稳定的 Terraform
resource graph，并证明列表重排不会改变地址或远端对象。发布过程由 grader 保存并审计 plan，再 apply
同一个 plan；之后 grader 会篡改一个真实 LocalStack 对象，要求 Terraform 精确识别并修复该漂移。

只修改 `starter/` 中的 Terraform HCL。不要编写脚本，也不要修改 fixtures 或 tests。

## Terraform 任务

1. 用 `jsondecode(file(...))` 解析 manifest，并规范化 application、environment、release 与 artifacts。
2. 建立彼此独立的合同检查，拒绝：
   - application/environment 与输入不一致，或 release 格式非法；
   - 空 artifacts、重复 artifact name、重复 enabled object key；
   - 非法 name/object key、空 content/content type，以及没有 enabled artifact。
3. 仅为 enabled artifacts 创建对象；以 artifact `name` 作为 `for_each` 稳定 key，禁止用列表下标。
4. 只创建一个 `aws_s3_bucket` 和一组 `aws_s3_object`。bucket 必须允许销毁并携带规范标签；对象必须使用
   `releases/<release>/<object_key>`，设置声明内容、content type、`etag`、metadata 和标签。
5. manifest 的数组重排必须得到相同的规范 SHA-256、相同地址、相同对象 key，并产生 clean plan。
6. 输出排序后的 artifact names、bucket name、object keys、精确 managed addresses，以及不包含制品正文的
   release contract。
7. AWS provider 只允许访问 loopback LocalStack：字面量 `test/test`，S3 path-style，精确的 `s3`、`sts`
   endpoints 和三项 skip flags。

## Grader 验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ./tests/grade.ps1
```

grader 会执行 **9 个 Terraform 1.6 兼容的普通 `command = plan` tests**，不使用
`mock_provider` 或 `override_*`。真实 LocalStack 阶段还会验证：

- 保存初始 plan、审计 JSON action/type/address，并 apply 同一个 saved plan；
- 使用重排 manifest 得到 detailed-exitcode 0；
- 带外修改一个对象后，saved repair plan 只更新该对象；
- apply repair plan 后内容恢复，随后 clean plan；
- 保存并审计 destroy plan、apply 同一个 plan，并确认 bucket 与对象零残留。

可只运行静态检查与 canonical tests：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ./tests/grade.ps1 -UnitOnly
```

## 考纲映射

- **1b / 1c**：plan、saved plan、apply、destroy 与资源行为；
- **1e**：refresh、带外漂移识别、精确修复与 clean plan；
- **2a / 2c / 2d / 2e**：复杂值、函数与表达式、`for_each`/lifecycle、conditions/checks；
- **3c**：自动化流程中的非交互 init/plan/apply 与 plan JSON 审计。

所有 AWS 调用只发送到本机 Docker LocalStack。grader 中的 PowerShell 只是测试基础设施，不是候选任务。
