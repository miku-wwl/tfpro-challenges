# Challenge 40：双 State 制品合同发布与运行时晋级 Capstone

难度：**98 / 100**  
考试模式建议：**75 分钟**  
首次完整学习与复盘：**150 分钟**

这道题的核心不是堆计算资源，而是完成一条可审计的发布链：`artifact` root 根据 manifest 把制品发布到 LocalStack S3，并输出版本化 `release_contract`；独立的 `runtime` root 只能通过 `terraform_remote_state` 消费这份合同，再把 release version 和 digest 晋级到双区域运行时。

## 目录与所有权

```text
starter/
├── artifact/                 # 独立 state：S3 bucket、objects、release_contract
└── runtime/                  # 独立 state：IAM、双区域 EC2 运行时
    └── modules/regional/     # 由调用方显式传入 default 或 aws.dr
fixtures/
├── manifest-v1.json
├── manifest-v2.json
├── runtime.json
├── runtime-reordered.json
└── ...独立负例
```

`artifact` 拥有 bucket 和 objects；`runtime` 不得读取 manifest、payload 或 S3 object，只能读取 artifact state 发布的合同。销毁必须按 `runtime -> artifact` 顺序。

## 任务

完成 starter 中 **11 处实质 TODO**：

1. 用 artifact name 建立稳定的 S3 object `for_each` 身份，并保留重复检测。
2. 用 6 个单一职责的 preconditions 分别校验 manifest schema、contract version、release version、数量+唯一性、字段+路径+digest 格式、真实 SHA-256；不得合并或填空壳。
3. 给 S3 objects 加入完整发布标签。
4. 发布 `contract_version = 1` 的 `release_contract`，包含 version、bucket、region、每个对象的 key/digest。
5. 把 DR AMI data source 路由到 `aws.dr`。
6. 把 JSON catalog 规范化为稳定的 `name@location` fleet identity，并拒绝重复。
7. 用 11 个独立 preconditions 校验远端合同和 runtime catalog；其中必须分别拒绝错误 bucket、不安全 object key 与非 64 位小写十六进制 digest。
8. 把 DR module 显式路由给 `aws.dr`。
9. 在 Launch Template user data 中注入合同版本、发布版本、bucket、artifact name/key/digest。
10. 用 release version、artifact digest、LT identity/latest version 构造受控替换哨兵。
11. 给 EC2 replicas 加入稳定身份、区域、release 与 artifact 追踪标签。

## 不变量

- Terraform 必须约束为 `~> 1.6`，AWS provider 为 `~> 5.100`。
- 所有 AWS provider 都使用字面量 `test/test`、三项 skip flag 和精确的 loopback LocalStack endpoints；endpoint 必须是带 1–65535 显式端口、无路径/查询/CR/LF 的完整 root origin。
- artifact root 仅配置 `s3`、`sts` endpoints；runtime 的 default 与 `aws.dr` 均仅配置 `ec2`、`iam`、`sts`。
- fleet identity 为 `name@location`；replica identity 为 `name@location#NN`。只调整 JSON 行顺序必须是零变更。
- v1→v2：artifact 仅允许 manifest guard 与两个 S3 object 原地更新；runtime 仅允许 contract guard、两个 LT 原地更新，以及两个 revision sentinel 和两个 EC2 的受控替换。
- 不得使用 Auto Scaling。LocalStack Community 当前不包含 Auto Scaling API，本题用 Launch Template + 少量稳定 EC2 replicas 模拟发布控制面；真实计算规模只有 2 台。
- 全部配置只允许两处 `ignore_changes`：Launch Template 的 `[tag_specifications]`，以及 EC2 replica 的 `[launch_template]`（替换由 revision sentinel 精确触发）。S3 object 禁止忽略任何变更；release version/digest 仍必须由 LT user data、S3 tags 和 EC2 tags 真实承载。

## 建议执行顺序

先启动仓库的 LocalStack（需要 `s3,ec2,iam,sts`），然后完成代码并运行评分器：

```powershell
pwsh ./tests/grade.ps1
```

评分器会在隔离副本中执行：

1. `fmt / init / validate`。
2. Artifact **7** 个、Runtime **16** 个 canonical runs，共 **23** 个。
3. v1 artifact saved plan 与 plan JSON gate，然后 apply。
4. v1 runtime saved plan 与精确 create gate，然后 apply。
5. v1、v2 都真实回读两个 S3 payload 及四项对象 tags，并回读 IAM、双区域 LT user data/tags 与 EC2 placement/tags。
6. runtime catalog reorder 零变更。
7. v2 artifact saved plan：精确 3 个原地 update。
8. v2 runtime saved plan：精确 2 LT update、2 sentinel replacement、2 EC2 replacement，加 1 contract guard update。
9. 制造单实例 Name tag drift，要求精确 1 个原地 update 并恢复。
10. 两个 root 重复 clean plan，最后按 runtime→artifact 逆序销毁并检查零残留。

直接运行 runtime 前，artifact 必须已经 apply 并生成独立的 `terraform.tfstate`。不要手工复制输出，也不要让 runtime 读取 artifact 配置文件。
