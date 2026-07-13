# Challenge 30：三层 State 双区域发布与恢复演练

难度：**98 / 100**　建议用时：**150 分钟**

## 场景

一套平台被拆成 `foundation`、`platform`、`workloads` 三个独立 root module 和三份
state。foundation 发布双区域网络合同；platform 只能通过 remote state 消费网络合同，
并发布 security group、SNS、DynamoDB 合同；workloads 再消费前两份合同，根据 CSV 在
primary/DR 创建稳定寻址的 artifact bucket 和 manifest object。所有 AWS 调用都必须
走本机 LocalStack。

## 任务

1. 完成三个 root 的变量验证、LocalStack provider 和明确的 primary/DR alias 路由。
2. foundation 在两个区域分别创建 VPC/subnet，输出版本为 1、对称的 `network_contract`。
3. platform 只读取 foundation 输出，不跨 state 引用资源；在两个区域创建 SG、SNS topic、
   DynamoDB table，并发布 `platform_contract`。
4. workloads 规范化、过滤并展开 CSV；仅允许 `primary`/`dr` location，用
   `name@location` 作为稳定且唯一的 key，CSV 重排行不得改变资源地址。
5. 用两个静态 module block 将 primary 与 DR 实例交给正确 provider，child module 不得
   自行配置 provider。
6. platform/workloads 必须拒绝未知合同版本或与 provider region 不一致的上游合同。
7. manifest 必须编码 network 与 platform 合同；输出部署合同及按 owner 排序分组。
8. 严格按 foundation → platform → workloads apply，重复 plan 三次都必须为零。
9. 严格反向 destroy；任何阶段失败都应保留可诊断信息，并能安全重跑。

## 验收

先确保 LocalStack edge endpoint 在 `http://localhost:4566`，然后运行：

```powershell
pwsh ./tests/grade.ps1
```

grader 会运行三个 root 的 mock 合同测试，再执行真实 LocalStack 三 state 端到端流程。
完成后仓库中不应留下 state、plan、`.terraform` 或云资源。

## Professional 大纲

综合覆盖 state 边界、remote-state contract、模块接口、provider graph、复杂 collection、
稳定资源身份、执行顺序、幂等性、故障恢复与自动化交付。这是本组最接近综合实操题的一题。
