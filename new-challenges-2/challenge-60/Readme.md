# Challenge 60：LocalStack 模块化、Provider Routing 与生命周期 Capstone

这是一道和 Challenge 3.5 难度接近的整合题。Starter 是可运行的单体 release：S3
bucket/object、IAM role 与容量 controller 都在 root。你要按顺序记录基线、零替换拆成三个
modules、接入三个 provider aliases、查询 AMI/Subnet、定向发布 Launch Template，最后处理
desired capacity 的生命周期所有权。

## 官方考试目标

- **1b / 1c / 1e**：Plan/apply options and state-preserving refactors
- **2b / 2d**：Data sources, targeting, dependencies, and lifecycle
- **4a / 4b / 4d**：Create/use modules and refactor existing configuration
- **5b**：Configure providers, including aliasing, versioning, sourcing, and managing upgrades

所有 AWS API 都指向 LocalStack；不使用 Community 版不支持的真实 ASG。

## Starter 状态

~~~powershell
Set-Location .\new-challenges-2\challenge-60
terraform init
terraform fmt -check
terraform validate
terraform plan '-out=c60-baseline.tfplan'
terraform apply .\c60-baseline.tfplan
terraform output monolith_contract
terraform state list
~~~

应有四个 managed addresses。保存 bucket、object key、role ARN 与 capacity=1，删除 baseline
plan。后续重构不得重建前三个 AWS 对象。

## Task 1：建立重构前证据

~~~powershell
terraform state pull | Set-Content -Encoding utf8 .\c60-before-state.json
aws --endpoint-url=http://localhost:4566 s3api head-bucket --bucket tfpro-c60-release
aws --endpoint-url=http://localhost:4566 iam get-role --role-name tfpro-c60-compute
terraform plan
~~~

确认 baseline clean。`c60-before-state.json` 是临时审计证据，不可作为后续配置输入，也不要
手工编辑 state。

## Task 2：把四个对象拆到三个 Child Modules

练习期间临时创建：

| Module | 接管对象 | Root 保留 |
|---|---|---|
| `modules/storage` | bucket、manifest object | manifest 业务输入 |
| `modules/identity` | IAM role | `aws_iam_policy_document.compute_trust` |
| `modules/compute` | `terraform_data.desired_capacity` | 容量目标输入 |

每个 module 声明需要的 provider requirement、输入与结构化 output；child 内不能写 provider
configuration。Root 调用三者，并添加四条精确 `moved` blocks。

先删除 root resources 而不写 moved，观察 plan 会 delete/create，**不要应用**。补齐 moved 后：

~~~powershell
terraform fmt -recursive
terraform init
terraform plan '-out=c60-modules.tfplan'
terraform show c60-modules.tfplan
~~~

允许地址迁移与 output 变化；已有 AWS objects 不得 create/update/delete/replace。

## Task 3：应用迁移，再引入三个 Provider Aliases

先应用同一迁移计划并记录新地址：

~~~powershell
terraform apply .\c60-modules.tfplan
terraform state list
~~~

然后在 root 添加 `aws.storage`、`aws.identity`、`aws.compute` 三个完整 aliases：

- storage 配 S3/STS endpoints；
- identity 配 IAM/STS；
- compute 配 EC2/STS；
- 全部 Region `us-east-1`、LocalStack 假凭证与三项 skip flags。

用 module call 的 `providers` map 显式传入。根 data source 后续使用 `aws.compute`。Plan
必须无 AWS resource actions；alias 名称不会自动完成 module routing。

## Task 4：用 Data Sources 建立 Compute Input

在 root 添加：

- 最新 available Amazon Linux 2023 x86_64 `aws_ami` 查询；
- `us-east-1a` 默认 `aws_subnet` 查询；
- 两者都显式绑定 `aws.compute`。

扩展 compute module 输入，在其中创建 `aws_launch_template.release`：

- name prefix `tfpro-c60-`；
- image ID 来自 AMI query；
- instance type `t3.micro`；
- instance tags 含 Challenge 60 与 release v1。

Subnet 不必写入 Launch Template；它进入最终 compute contract，供未来 instance/ASG 消费。

## Task 5：定向发布后回到完整 Workflow

先生成 targeted saved plan，地址必须使用完成后的 module 地址：

~~~powershell
terraform plan '-target=module.compute.aws_launch_template.release' '-out=c60-target.tfplan'
terraform show c60-target.tfplan
terraform apply c60-target.tfplan
~~~

Target 只用于这次分阶段恢复/发布，不是常规 workflow。随后：

~~~powershell
terraform plan '-out=c60-full.tfplan'
terraform show c60-full.tfplan
terraform apply c60-full.tfplan
terraform plan
~~~

完整 plan 负责发现 target 未覆盖的 output/依赖变化；最终必须 `No changes`。发布
`release_contract`，包含 storage、identity、AMI、subnet、launch template 与 capacity。

## Task 6：交接 Desired Capacity 所有权并清理

把 compute module 的 capacity input 从 1 改为 2，先 plan，应看到
`terraform_data.desired_capacity` update。然后给 `input` 添加 `ignore_changes` 再 plan：
应无变更，state/output 仍为 1。这保留 Challenge 3.5 的 ASG desired-capacity 概念，但明确
surrogate 不会真实扩缩 EC2。

保持完成态配置执行：

~~~powershell
terraform destroy -auto-approve
aws --endpoint-url=http://localhost:4566 s3api head-bucket --bucket tfpro-c60-release
aws --endpoint-url=http://localhost:4566 iam get-role --role-name tfpro-c60-compute
~~~

两个 API 查询都应报不存在。然后删除本题临时 modules、plans、state evidence、`.terraform`、
lockfile/state，恢复 `challenge-60.tf` 单体 starter。最终目录只能有两份源文件。

## LocalStack 与考试边界

- LocalStack EC2 不启动 guest；验收 Launch Template schema、state 与 API 即可。
- Community 版没有本题可依赖的 ASG API，所以 `terraform_data` 只模拟容量字段所有权。
- Targeted apply 后必须回到完整 plan；module/provider 重构必须用 state/物理 ID 证明零替换。
