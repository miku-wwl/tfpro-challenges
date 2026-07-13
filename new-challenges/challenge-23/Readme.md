# Challenge 23：零替换网络重构

难度：**96/100**　建议时限：**150 分钟**

你接手了一个用 `count` 管理 VPC、两个 subnet 和两个 security group 的旧 root module。资源已经存在于 state，调用方还在读取松散的 v1 outputs。你的任务是在**同一个 state** 中把实现迁移成具名 `for_each` 嵌套模块，同时保证计划为零基础设施变更。

## 交付目标

只修改 `starter/`：

1. root 只负责 provider、输入、`module "network"`、moved blocks 和 v2 output。
2. `modules/network` 管理 VPC，并分别调用 `modules/subnet` 与 `modules/security-group`；两个子模块都必须使用 `for_each` 的业务名称作为实例 key。
3. 为五个旧地址写显式 `moved` blocks：
   - `aws_vpc.main[0]`
   - `aws_subnet.this[0]`、`aws_subnet.this[1]`
   - `aws_security_group.this[0]`、`aws_security_group.this[1]`
4. 发布单一 `network_v2` output，至少包含 `schema_version = 2`、VPC、按名称索引的 subnets 和 security groups。
5. 迁移后的保存 plan 必须只有 `no-op`，并能 clean plan、destroy。

基线 key 固定为 `app-a`、`app-b`、`app`、`ops`。这正是 moved block 需要写成显式映射的原因：Terraform 不会自动猜测索引与业务名称的对应关系。

## LocalStack 安全边界

本题只允许 `http://localhost:4566`（也接受其他 loopback 写法），固定假凭证 `test/test`，endpoint 仅使用 EC2 与 STS。不要放入真实 AWS 凭证。LocalStack 的 EC2 行为不等同于真实 AWS；本题验证的是 Terraform 地址、状态与模块接口，不验证真实网络转发。

## 验收

```powershell
pwsh ./tmp2/challenge-23/tests/grade.ps1
```

grader 会先做结构契约与 mock test，再在临时目录中创建 legacy state、覆盖候选实现、检查 plan JSON 的 `previous_address` 和 actions、应用保存 plan、检查 v2 output、clean plan，并按精确顺序销毁。所有临时名称均唯一。
