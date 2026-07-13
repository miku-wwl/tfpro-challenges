# Challenge 19：接管既有资源、迁移 State 与漂移恢复

**难度：95 / 100（Terraform Professional = 100）**  
**建议时间：100 分钟**

你接手了一个发布归档系统。S3 bucket 与 DynamoDB table 已存在，但不在当前 state 中；旧版本 Terraform 又以旧地址管理了发布清单，同时有一个已经退出配置、但必须暂时留在 S3 中的通知对象。

完成 `starter/`，让统一 grader 可以按以下顺序完成一次真实迁移：

1. 通过 declarative `import` 接管既有 bucket 和 table，禁止重建。
2. 用 `moved` block 将旧地址迁移到 `aws_s3_object.release_manifest` 与 `terraform_data.inventory`。
3. 由 runbook 执行 `terraform state rm aws_s3_object.retired_notice`；不得在新配置中继续声明它。
4. 接管后 plan 必须为 clean，state 中不得留下 legacy 地址。
5. grader 会绕过 Terraform 修改 `releases/manifest.json`。先执行并应用 refresh-only plan，使 state 如实记录远端漂移；随后普通 plan 必须提出修复，apply 后对象内容恢复，最终再次 clean。
6. 所有资源只能访问本机 LocalStack，凭证固定为 `test/test`。

关键约束：

- Terraform `required_version = "~> 1.6"`，AWS provider `~> 5.100.0`。
- bucket 名与 table 名必须由 `name_prefix` 稳定推导。
- S3 bucket 必须能在销毁时清理 grader 留下的非托管对象。
- 不要编辑 fixtures 或 tests，也不要把真实 AWS 凭证写进任何文件。

版本说明：本题 Terraform 配置（包括两个静态 `import` block）兼容 Terraform 1.6；`terraform test` 的 `mock_provider` 是 Terraform 1.7 才加入的测试能力，因此运行 canonical mock grader 需要 Terraform **>= 1.7**。在 1.6 环境中可完成真实 migration workflow，但应跳过 mock test 阶段。

运行（LocalStack 应监听 `http://localhost:4566`）：

```powershell
pwsh ./tmp2/challenge-19/tests/grade.ps1
```

grader 会为每次运行生成唯一前缀和临时目录，完成 bootstrap、legacy state、接管、漂移、修复、clean plan 与 destroy；清理范围仅限本次创建的资源。
