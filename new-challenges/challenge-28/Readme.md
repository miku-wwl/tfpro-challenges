# Challenge 28：双 State 双区域应用合同

难度：**96 / 100**　建议用时：**110 分钟**

## 场景

`network` 与 `application` 是两个独立 root/state。network 在 LocalStack 的主区域和
灾备区域创建 VPC/subnet，并只通过 `network_contract` output 对外发布合同。
application 使用 `terraform_remote_state` 读取合同，再依据 CSV 把应用的 S3 artifact
bucket 和 SNS topic 路由到正确区域。

## 任务

1. 修复 network 的 `aws.dr` 资源路由，并发布带 `contract_version = 1` 的完整、最小双区域合同。
2. `target_environment` 只允许 `dev/stage/prod`；显式转换 CSV bool/number/string。
3. 只选择目标环境且启用的应用；`both` 展开为 primary/dr 两份部署，并拒绝未知 location。
4. 使用 `application@location` 作为稳定 key，拒绝重复 key，CSV 重排不得改变资源地址。
5. 使用两个静态 module block，DR 显式映射 `aws.dr`；不得动态选择 provider 引用。
6. 子模块创建 S3 bucket 和 SNS topic，并输出 region/owner/port 合同。
7. 输出排序后的 deployment keys、完整地址和按 owner 分组的 key。
8. 拒绝未知版本的 network contract，以及合同 region 与 provider region 不一致。
9. 两个 root 分别获得零变更 plan；销毁顺序必须 application → network。

## LocalStack

provider 只能使用 `test/test`，所有 EC2/S3/SNS/STS endpoint 来自 loopback
`localstack_endpoint`。运行：

```powershell
pwsh ./tests/grade.ps1
```

grader 会在临时副本中运行 canonical mock tests 和真实 LocalStack apply/plan/destroy。

## 不变量与安全边界

- 两个 state 不合并，不复制或手改 state JSON。
- 下游不能直接引用 network resource 地址。
- S3 使用 path-style；禁止真实 AWS endpoint/credential。
- grader 只清理由本次唯一 run id 创建的资源。

## Professional 大纲

覆盖 state 生命周期、复杂 HCL、remote state、自动化顺序、module/provider alias 合同与
provider troubleshooting。
