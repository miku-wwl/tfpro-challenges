# Challenge 53：双 Region Provider Alias 与六地址零动作模块化迁移

难度：**95 / 100**；考试模式 **85 分钟**，首次完整学习 **150 分钟**。评级：**A**。

旧 root 在 `us-east-1` 与 `us-west-2` 管理共享 IAM identity，以及两套 security group/launch template。
现在要迁入一个 identity module 和两个复用的 regional module；DR module 必须显式接收 `aws.dr`，不能在 child module
中自行配置 provider。真实资源不得因地址重构而改变。

只修改 `starter/`：

1. 严格解析 `fixtures/regions.json`，拒绝顶层/region schema、版本、重复或缺失 key、区域映射和字段错误；数组重排必须稳定。
2. identity module 管理共享 IAM role/profile；regional module 通过 aliased provider 读取外建 subnet 与真实 AMI，并管理 SG/LT。
3. root 必须静态调用 `primary` 与 `dr` 两个 regional modules，分别映射 `aws` 和 `aws.dr`；禁止 module 内 provider block。
4. 六个 `moved` blocks 精确迁移 role、profile、两个 SG 和两个 launch template；迁移 saved plan 必须零 create/update/delete/replace。
5. launch template 保持 region、AMI、subnet 所属 VPC、shared profile、instance type、SG 与 user-data 合同；SG/identity 保持完整标签合同。
6. provider 只允许 loopback root-origin LocalStack `ec2,iam,sts` endpoints、字面量 `test/test` 与三项 skip flags。
7. grader 使用 Terraform 1.6.6 运行 7 个普通 plan tests；Full 在两个 LocalStack region 外建网络、apply legacy、交接 state、审计六个 `previous_address`、验证双区真实资源与 reorder clean；随后篡改 DR SG tag，要求 saved plan 只 update DR SG，修复后 destroy 并检查双区/IAM 零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```
