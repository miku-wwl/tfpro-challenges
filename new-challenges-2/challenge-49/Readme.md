# Challenge 49：给 Child Module 传入两个显式 Provider Slots

Starter 已用 root 中的两个 aliases 创建一对跨 Region buckets。你的目标不是新建另一对，
而是把资源零替换地迁入可复用 child module，并让 module 明确声明 `aws.primary` 与
`aws.dr` 两个 slots。这个练习区分 provider requirement、provider configuration 和 module
call mapping 三个经常混淆的层次。

## 官方考试目标

- **4b**：Use a module in configuration
- **5b**：Configure providers, including aliasing, versioning, sourcing, and managing upgrades
- **5d**：Troubleshoot provider errors
- 辅助 **1e**：Preserve resource identity while changing addresses

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-49
terraform init
terraform apply -auto-approve
terraform output starter_buckets
terraform state list
~~~

应得到两个 root resource 地址与两个物理 bucket。记录名称和 state serial；本题后续不得删除
或重建它们。目录初始只有两份源文件。

## Task 1：先创建不含 Provider Configuration 的 Module

临时创建 `modules/routed_pair/main.tf`。Child module 必须：

- 声明 AWS provider source 与兼容 `5.x` 的最小版本约束；
- 在 `configuration_aliases` 中声明 `aws.primary`、`aws.dr`；
- 接收两个 bucket names 与共同 tags；
- 创建 primary、DR 两个 bucket，各自绑定对应 slot；
- 输出包含两个 bucket IDs 的对象。

不要在 child module 内写 `provider "aws"` block，也不要复制 LocalStack credentials。

~~~powershell
terraform fmt -recursive
terraform init
terraform validate
~~~

此时 root 还没调用 module，因此 state 和远端对象都不应变化。

## Task 2：在 Root 建立静态 Providers Mapping

在 root 调用一次 `module.routed_pair`，通过 `providers` map 完成：

| Child slot | Root configuration |
|---|---|
| `aws.primary` | `aws.primary` |
| `aws.dr` | `aws.dr` |

传入现有物理名称与 tags。先暂时保留 root 的两个 resource blocks，然后运行 validate。若漏掉
任一 slot，记录 Terraform 的 warning/error；补齐后再继续。Provider mapping 必须是静态
引用，不能由变量或条件表达式动态选择。

## Task 3：先观察没有迁移声明的错误计划

删除 root resource blocks，但先不要添加 `moved`。运行：

~~~powershell
terraform plan
~~~

预期计划把两个 root 地址删除、在 module 下新建两个地址。不要应用。这个计划说明“物理
参数相同”不等于“Terraform 知道它们是同一对象”。

## Task 4：声明两条精确地址迁移

添加恰好两条 `moved` blocks：

- root primary → module 内 primary；
- root DR → module 内 DR。

~~~powershell
terraform plan '-out=c49-move.tfplan'
terraform show -json .\c49-move.tfplan |
  Set-Content -Encoding utf8 .\c49-move.json
~~~

计划允许地址 move 和 output 变化，但 AWS resources 的 actions 必须全为 `no-op`；不得有
create、update、delete 或 replace。

## Task 5：应用地址迁移并核对 Provider 路由

~~~powershell
terraform apply .\c49-move.tfplan
terraform state list
terraform output routed_pair_contract
terraform plan
aws --endpoint-url=http://localhost:4566 s3api get-bucket-location --bucket tfpro-c49-primary
aws --endpoint-url=http://localhost:4566 s3api get-bucket-location --bucket tfpro-c49-dr
~~~

最终 state 只含两个 module resource 地址，物理名称不变，plan 为 `No changes`。Primary
location 可为 null，DR 应为 `us-west-2`。

## Task 6：从完成态安全清理回 Starter

先保持 module 文件和 provider mappings 完整执行：

~~~powershell
terraform destroy -auto-approve
~~~

确认两个 buckets 已消失后，删除本题临时创建的 `modules`、plan/JSON、`.terraform`、
lockfile 和 state，再把 `challenge-49.tf` 恢复 starter。最终：

~~~powershell
Get-ChildItem -Recurse -Force
~~~

只能看到 `Readme.md` 与 `challenge-49.tf`。不要先删 module 再 destroy，否则 state 中的
module resources 将变成配置外对象。

## Terraform 1.6 边界

- Child module 的 `configuration_aliases` 属于 provider requirement，不提供 Region 或凭证。
- Module call 的 `providers` map 负责把 root configurations 绑定到 slots。
- `moved` 保存重构意图；`terraform state mv` 可以操作同一 state，但不会把意图留在代码中。
