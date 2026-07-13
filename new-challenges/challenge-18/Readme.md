# Challenge 18 · 双区域多 State 平台交付

**建议时间：** 120 分钟  
**难度：** Expert（Terraform Professional = 100 时，本题约 96）  
**运行方式：** LocalStack 端到端 + AWS mock provider 单元测试

## 场景

平台由两个独立 root module 组成：`foundation` 管理主区域和灾备区域网络，
`workload` 通过 `terraform_remote_state` 消费网络合同，再根据 CMDB CSV 在正确
区域实例化服务安全组。CSV 行顺序不稳定，两个 root 的 state 生命周期彼此独立。

starter 同时包含数据筛选、provider 映射、模块接口和输出稳定性缺陷。你必须修复
这些缺陷，但不能把两个 state 合并，也不能写入任何真实凭证。

## 任务

1. 在 `foundation` 中配置默认 `aws` provider（`us-east-1`）以及 `aws.dr`
   provider（`us-west-2`），并确保灾备资源使用正确 provider。
2. 输出名为 `network_contract` 的稳定 map，key 只能是 `primary` 和 `dr`；每个
   value 包含 `vpc_id`、`subnet_id` 和 `region`。
3. 在 `workload` 中使用 `terraform_remote_state` 读取上述合同。不得直接引用
   `foundation` 的资源或复制 VPC/subnet ID。
4. 解析 `fixtures/services.csv`，规范化 string/number/bool，只保留目标环境中
   `enabled = true` 的记录。
5. `target_environment` 只接受 `dev`、`stage`、`prod`。
6. 将 `primary` 服务交给默认 provider，将 `dr` 服务交给 `aws.dr`；`both`
   服务必须在两个区域各创建一次。provider 引用必须静态映射到 module block。
7. 子模块必须声明 provider requirements，并为每个部署创建一个 security group
   和一条 ingress rule；端口来自 CSV，不得硬编码服务数据。
8. 资源身份必须由 `service@location` 构成，CSV 重排不能改变 module/resource
   地址。所有 list 输出显式排序。
9. 输出 `deployment_keys`、`deployment_addresses` 和按 owner 分组的
   `deployments_by_owner`。
10. 所有 provider 只能使用固定 LocalStack `test/test`，EC2/STS endpoint 必须来自
    loopback `localstack_endpoint`；禁止写入真实凭证。

## 验收

在 challenge 目录执行：

```powershell
pwsh ./tests/grade.ps1
```

也可以分别在两个 starter root 中执行 `terraform fmt -check`、
`terraform init -backend=false`、`terraform validate`。grader 会临时复制 canonical
tests，执行完后删除测试副本。

## 必须保持的不变量

- foundation 和 workload 保持独立 state。
- remote-state output 是两个 root 之间唯一的数据合同。
- CSV 重排不改变服务资源身份。
- disabled 和其他 environment 的服务不会进入计划。
- 灾备模块显式接收 `aws.dr`，不能依赖隐式继承。
- 只访问本机 LocalStack，不在仓库生成真实凭证。

## 对应 Professional 大纲

覆盖 1e、2a/2c/2d/2e、3b/3c/3d、4a/4b/4d、5b/5c/5d。
