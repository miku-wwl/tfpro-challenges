# Challenge 25：配置制品的生命周期、导入与漂移恢复

难度：**95/100**，建议限时 110 分钟。

你要把一个版本化 JSON 配置同时发布到 S3 与 DynamoDB。团队要求资源身份稳定、内容变更可追踪、关键 bucket 不可被误删，并能处理 state 丢失和带外漂移。

## 任务

1. 将 endpoint 限制为 loopback，凭证固定 `test/test`；S3、DynamoDB、STS 都必须走 LocalStack。
2. 验证环境、正整数配置版本及 JSON 文档合同：文档内 `application`、`environment` 必须匹配变量，`features` 必须为非空对象。
3. 使用 `terraform_data.config_revision` 保存版本和 SHA-256；版本或内容变化时必须通过 `triggers_replace` 触发 replacement。
4. 创建 S3 bucket、DynamoDB table、S3 object 和 `aws_dynamodb_table_item`。两个发布载荷必须包含同一个版本及摘要。
5. S3 object 与 table item 使用 `replace_triggered_by`；加入有意义的 `precondition` 和 `postcondition`。S3 bucket 必须设置 `prevent_destroy = true`。
6. 输出 `revision_identity`、`bucket_name`、`object_key`、`table_name`，且不得输出配置正文。
7. 演练操作流程：

```powershell
terraform apply
terraform state rm aws_s3_bucket.config
terraform import aws_s3_bucket.config <bucket-name>
terraform plan                 # 必须无变更
terraform plan -refresh-only   # 记录带外漂移
terraform apply                # 恢复声明内容
```

8. 完成后运行 `pwsh ./tests/grade.ps1`。grader 会在唯一命名的 LocalStack 资源上真实执行 apply、state rm/import、带外对象漂移、refresh-only、恢复、clean plan，并验证 `prevent_destroy` 确实阻止普通 destroy；最后安全清理资源。

若你在 starter 目录手工 apply，普通 destroy 按设计会被 bucket 的保护挡住。确认只清理本题资源后，先执行 `terraform state rm aws_s3_bucket.config`，再 destroy 其余资源，最后删除 LocalStack 中已经为空的 bucket；不要为了方便移除生命周期保护后直接操作真实 AWS。

不要修改 fixtures 或 tests。LocalStack 用于练习状态与生命周期行为，并不等同于真实 AWS 的全部一致性语义。
