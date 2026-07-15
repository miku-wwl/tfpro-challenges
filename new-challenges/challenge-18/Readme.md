# Challenge 18：双区域、双 S3 State 与静态 Provider 分支综合题

难度：**97 / 100**；考纲契合度：**A**；考试模式 **110 分钟**，首次完整学习 **170 分钟**。

`foundation` 与 `workload` 是两个 S3-backed root。foundation 用两个 provider aliases 调用 regional-bucket
module，workload 通过 S3 `terraform_remote_state` 获取 bucket contract，再把 CSV 中 primary/dr/both 服务
静态分支到两个 provider-mapped service modules。只修改 `starter/` HCL，不编写脚本。

## Terraform 任务

1. 两个 root 都使用 partial S3 backend；LocalStack backend 参数由 grader 注入。
2. foundation 只定义 `aws.primary`/`aws.dr`，正确映射到两个 child calls；child 创建 S3 bucket 并查询 caller identity。
3. foundation 输出 schema v1 的最小 `platform_contract`，exact keys 为 primary/dr，字段为 bucket/region/account。
4. workload 用 S3 remote state 读取该 output；规范化 CSV，过滤 environment/enabled，校验字段并把 both 展开两次。
5. `service@location` 是稳定身份；primary/dr 使用两个静态 module blocks 和显式 provider mappings。
6. child module 在 foundation-owned bucket 创建 S3 object，使用 content/etag/metadata/tags 和 schema precondition。
7. 重排 CSV 必须 clean；outputs 排序并按 owner 分组；销毁必须 workload → foundation。
8. 四个 providers 与 remote state 仅使用 loopback LocalStack、字面量 test/test、S3/STS endpoints 和 skip flags。

## 验收

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

grader 使用 Terraform 1.6.6 跑 **9 个普通 plan tests**（无 mock/override），在真实 S3 remote state 上验证
两个 roots；完整阶段审计/apply saved plans、验证双区域 bucket location、CSV 双区域展开、state ownership、
重排 no-op、真实对象漂移与精确 repair、两个 clean plans、逆序 saved destroy 和所有 S3 零残留。

## 考纲映射

- **1a–1e**：S3 init、saved plan/apply/destroy、drift repair；
- **2a–2e**：checks、caller data、CSV/HCL 变换、静态 provider 分支、复杂 output；
- **3b / 3c / 3d**：两个 S3 state、自动化 workflow 与跨配置合同；
- **4a / 4b**：两个可复用 modules 及 provider injection；
- **5b / 5c / 5d**：aliases、LocalStack authentication 与 endpoint 排障。

Candidate AWS workload 仅使用公开考试资源清单中的 S3 bucket/object、caller identity、S3 backend 和 S3 remote state。
