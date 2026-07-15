# Challenge 40：双 State 制品合同与跨区域滚动发布 Capstone

难度：**97 / 100**；考试模式 **85 分钟**，首次完整学习 **150 分钟**。评级：**A**。

交付链拆成 `artifact` 与 `runtime` 两个独立 root、两份真实 S3 state。artifact 校验版本化 manifest，把 payload 发布到 S3 并输出不可越界的 release contract；runtime 只能通过 S3 remote state 消费合同，在 grader 预置的 primary/DR 网络上交付两组 EC2 fleet。随后必须把 manifest v1 升级到 v2，并用真实 saved-plan JSON 证明变更范围。

只修改 `starter/`：

1. 两个 root 都声明空 partial S3 backend；禁止 local backend/state 路径交接。
2. artifact 规范化 manifest，以 artifact name 为稳定 key；独立阻断顶层 schema、contract version、release version、重复 name、非法字段/路径/key/digest，以及 payload digest 不匹配。
3. artifact 只管理一个 versioned-name、`force_destroy` 的 S3 bucket 与每项一个 `aws_s3_object`，发布包含 run、region、release、bucket、key 与 sha256 的 `release_contract` v1。
4. runtime 只通过 S3 `terraform_remote_state` 消费 release contract，并验证 contract version/run/region/bucket/release/object key/digest。
5. runtime 用 default/`aws.dr` 查询 grader 外建的两个 `data.aws_subnet` 与双区 `data.aws_ami`；禁止管理 VPC/subnet。
6. 规范化四字段 JSON fleet 目录，以 `name@location` 为稳定 key；独立阻断 schema、空目录、重复 key、非法字段/location/instance type 与未发布 artifact 引用。
7. 创建一个 IAM role/profile，并把两个静态 regional module 分别路由到 default/`aws.dr`；child 不得配置 provider。
8. 每个 regional module 创建一个 SG，并为每个 fleet 创建一个 launch template 与一个直接落实同等 AMI/network/profile/user-data 合同的 EC2 instance。release version、artifact key/digest 必须进入 user-data 与 tags；注意 launch template 的 `user_data` 需要显式 base64，而 `aws_instance.user_data` 接收原始正文并由 provider 编码。EC2 的 user-data 是启动期合同，必须设置 `user_data_replace_on_change = true` 与 `create_before_destroy`，让 v2 以先建后删的 replacement 发布，而不是只改不会自动重跑的实例元数据。
9. 禁止 `terraform_data`、capacity/replica 模拟、`ignore_changes`、mock/override 与候选脚本；所有 AWS 类型必须在 Professional 公布范围内。
10. grader 先审计并 apply v1 saved plans，再将 artifact manifest 切到 v2；它会从 Terraform 1.6/AWS provider 的实际 plan 中严格锁定对象与 launch-template 的原地 update、instance 的 create-before-destroy replacement，应用后回读 S3/LT/EC2 并确认实例身份已经滚动，再验证目录重排、单 tag drift、双 clean plan、runtime→artifact 逆序 destroy 与零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

## Professional 大纲定位

覆盖 partial S3 backend、remote-state contract、S3 bucket/object、provider alias、subnet/AMI data、IAM、SG、launch template、EC2、modules、稳定 collection、saved plan JSON、升级、drift 与 destroy。评级 **A（97/100）**。
