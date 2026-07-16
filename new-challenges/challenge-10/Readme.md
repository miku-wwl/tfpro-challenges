# Challenge 10：单体配置到多模块的零替换迁移

## 场景

生产服务目录仍是 root module 中的 `count` 资源。平台团队要求把每个服务迁入独立
child module，并把接口升级为 v2：以对象接收服务参数、支持 optional healthcheck、
统一 context tags，同时对外输出保持兼容。已有实例不能重新创建。

难点不是“最终配置能 apply”，而是从旧 state 到新地址的**第一次迁移计划**必须只有
地址移动和 output 变化，不得出现任何资源 create/delete/replace。

## 官方大纲 Objective

- 1b/1c：保存并审阅迁移 plan，再精确 apply 该 plan。
- 1e：检查 state 地址和 plan JSON 中的 `previous_address` / actions。
- 2a：设计并调用可复用 child module。
- 2c：演进 module input/output contract，保持调用方兼容。
- 2d：从 `count` 迁移为稳定的 `for_each`，用 moved block 保留身份。

## 任务

1. 在一个空工作目录应用 `fixtures/legacy`，得到三个旧地址：
   `terraform_data.service[0..2]`。
2. 把资源实现迁入 `modules/service`，root 以服务名 map 调用模块。

   子模块内部的资源名称必须直接使用：

   ```hcl
   resource "terraform_data" "this" {
     # 服务配置字段
   }
   ```

   这里的 `this` 是资源标签，不是服务名称；它决定后续最终地址为
   `module.service["name"].terraform_data.this`。请从一开始就使用该名称，
   避免先创建 `terraform_data.service` 后再额外增加一次资源地址迁移。

> [!NOTE]
> 如果输入变量是 `list(object)`，不能直接用于 `for_each`，也不能直接使用
> `toset(var.services)`，因为 Terraform 的 `for_each` 不接受对象集合。
> 可以先转换为以服务名为 key 的 map：
>
> ```hcl
> for_each = {
>   for service in var.services :
>   service.name => service
> }
> ```
>
> 这样会生成稳定的模块地址，例如
> `module.service["api"]`、`module.service["web"]` 和
> `module.service["worker"]`。
3. 将 `modules/service` 的 child module 接口升级到 v2：
   - root 每次调用模块时传入一个 `service` 对象，至少包含 `name`、`port`、
     `owner`、`tier`，并支持可选的 `healthcheck`；
   - root 传入一个 `context` 对象，其中包含 `environment` 和 `tags`，不要再将
     这两个值作为两个独立变量传入；
   - child module 内部使用 `terraform_data.this` 保存当前服务的配置字段，至少包括
     `name`、`port`、`owner`、`tier`、`environment` 和 `tags`；这里的“服务数据”
     就是这些输入配置值，不是额外创建的云服务；
   - child module 提供以下 outputs：
     - `contract_version`：固定为数字 `2`；
     - `manifest`：输出当前服务的 name、port、owner、tier、environment 和 tags；
     - `healthcheck`：输出服务的 healthcheck，未配置时必须为 `null`。

   升级接口时必须保持 `terraform_data.this.input` 中原有的服务字段和数值不变，
   以便后续 `moved` block 迁移时不会触发资源 replacement。

> [!NOTE]
> Terraform 的条件表达式语法是：
>
> ```hcl
> condition ? true_value : false_value
> ```
>
> 不要写成 `if condition ? ...`。如果需要输出真正的空值，应使用 `null`，不要使用
> 字符串 `"null"`；例如可选的 `healthcheck` 未配置时应输出 `null`。
4. 为每个旧地址写显式 moved block，目标为
   `module.service["name"].terraform_data.this`。
5. 保持底层 `terraform_data.input` 完全一致，避免借“接口升级”偷偷修改实例。
6. 学习保存和查看 Terraform Plan：
   - 使用 `terraform plan -out=migration.tfplan` 将 plan 保存为二进制计划文件；
   - 使用 `terraform show migration.tfplan` 以人类可读格式查看保存的计划；
   - 使用 `terraform show -json migration.tfplan > migration.json` 将计划转换为 JSON，
     便于脚本检查 resource actions；
   - 保存的 plan 可以传给 `terraform apply migration.tfplan`，确保 apply 使用的正是
     已审核过的计划。
7. apply 后检查最终 state 地址，再确认第二次 plan 退出码为 0。

`starter/` 是一个未完成的中间提交：资源虽然进入了 child module，但 root 仍以 `count`
调用扁平 v1 接口，没有任何 moved block，且忽略 healthcheck。它能被解析，却会让旧地址
全部重建；你必须把这个半成品继续演进到最终合同。

## 验收命令

```powershell
pwsh ./tests/grade.ps1 -CandidateDir ./starter
```

grader 会自行创建并清理 `.grade-work`，依次 apply legacy、覆盖候选配置、审阅 plan
JSON、apply moved state、运行 `terraform test`。

## 最终不变量

- 初次迁移 plan 的三个资源 action 全是 `no-op`，没有 create/delete。
- 最终 state 只有三个具名 module 资源地址，不再存在 root count 地址。
- `api` healthcheck 为 `/ready`；未配置的服务输出 `null`。
- 每个模块 contract version 都是 2；服务端口和原始 tags 未变化。
- 迁移 apply 后 plan 完全幂等。

## 安全边界

- 只使用内建 `terraform_data`，不访问 AWS、凭证或网络 API。
- 不允许用 `terraform state mv` 代替题目要求的可审计 moved blocks。
- 不允许删除 state、重新 apply 新配置、手改 state JSON 或接受资源 replacement。
- grader 只递归删除本题目录内的 `.grade-work`。

## 官方参考

- https://developer.hashicorp.com/terraform/language/modules/develop/refactoring
- https://developer.hashicorp.com/terraform/language/modules/syntax
- https://developer.hashicorp.com/terraform/language/meta-arguments/for_each
- https://developer.hashicorp.com/terraform/internals/json-format
