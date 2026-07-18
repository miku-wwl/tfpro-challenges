# Challenge 54：CLI Workspaces 的 State 隔离与数据分享边界

CLI workspace 让同一配置拥有多个 state instances，但它不是目录、分支，也不等同于 HCP
Terraform workspace。本题让 dev/prod 分别管理同名 resource address，却创建不同 bucket，
再证明 state、输入值与清理都必须按 workspace 单独执行。

## 官方考试目标

- **1e**：Manage resource state, including importing resources and reconciling resource drift
- **3d**：Share data across configurations and workspaces

HCP workspace 的访问控制与配置选项在 Challenge 57 单独练习；本题只操作 CLI workspaces。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-54
terraform init
terraform workspace list
terraform workspace show
terraform plan
~~~

初始只有 `default`。Plan 会提出创建 `tfpro-c54-default`，但不要应用；生产团队通常不希望
有人误在默认 workspace 部署真实环境。

## Task 1：先理解地址相同不代表 State 相同

检查配置中的地址始终是 `aws_s3_bucket.environment`。预测 dev/prod 中
`terraform state list` 会显示什么，再回答：

- workspace name 是否成为 resource address 的一部分；
- Terraform 切换 workspace 时改变的是配置、provider 还是 state selection；
- 仅靠 workspace 是否会自动改变所有物理名称。

本题通过 `terraform.workspace` 显式进入 bucket name/tags，防止两个 states 争抢同一对象。

## Task 2：保护 Default Workspace

给 bucket 添加 lifecycle precondition，要求 `terraform.workspace != "default"`，错误消息应
明确提示先选择命名 workspace。

~~~powershell
terraform fmt
terraform validate
terraform plan
~~~

预期 validation 成功，但 plan 被自定义条件拒绝。条件依赖当前 workspace，属于 plan-time
运行合同，不是 HCL syntax check。

## Task 3：创建并部署 Dev

~~~powershell
terraform workspace new dev
terraform workspace show
terraform plan '-out=c54-dev.tfplan'
terraform apply .\c54-dev.tfplan
terraform output workspace_contract
terraform state list
~~~

应创建 `tfpro-c54-dev`，contract release 为 `v1`。删除 dev saved plan；它只属于生成它的
state/config snapshot，不应跨 workspace 复用。

## Task 4：创建独立 Prod State

~~~powershell
terraform workspace new prod
terraform state list
terraform plan '-var=release=v2' '-out=c54-prod.tfplan'
terraform apply .\c54-prod.tfplan
terraform output workspace_contract
~~~

切到新 prod 后，apply 前 state 应为空；apply 后创建 `tfpro-c54-prod`，release 为 `v2`。
Dev bucket 仍存在。

## Task 5：切换并证明没有串改

~~~powershell
terraform workspace select dev
terraform output workspace_contract
terraform plan
terraform workspace select prod
terraform output workspace_contract
terraform plan '-var=release=v2'
aws --endpoint-url=http://localhost:4566 s3api list-buckets --query "Buckets[?starts_with(Name, 'tfpro-c54-')].Name"
~~~

Dev state 仍记住 v1，prod state 仍记住 v2。输入值不是 workspace 全局配置；若 prod 忘记继续
传 `-var=release=v2`，正常 plan 会提出把 prod 改回默认 v1。

与结对 AI 说明：Consumer 若要读取另一 workspace 的 outputs，需要配置正确 backend 与
workspace/key（例如 `terraform_remote_state`），不能靠当前 CLI workspace 自动穿透读取。

## Task 6：逐个 State 销毁并删除 Workspace

~~~powershell
terraform workspace select prod
terraform destroy -auto-approve '-var=release=v2'
terraform workspace select dev
terraform destroy -auto-approve
terraform workspace select default
terraform workspace delete prod
terraform workspace delete dev
~~~

确认两个 buckets 和两个命名 workspaces 都消失，再删除 plans、`.terraform`、lockfile 与
所有 local state，恢复未含 precondition 的 starter。最终目录只保留两份源文件。

## 边界与陷阱

- Saved plan、state CLI 与 destroy 都作用于当前 selected workspace。
- CLI workspaces 适合共享配置的轻量 state 隔离，不替代强权限边界或完全不同的系统架构。
- HCP Terraform workspace 是远端管理对象，具有变量、权限、执行模式等额外配置；不要与
  `terraform workspace` 命令创建的 state namespace 混为一谈。
