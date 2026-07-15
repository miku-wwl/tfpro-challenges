# Challenge 49：双区域 Launch Template 发布与受控替换

难度：**95 / 100**；考纲契合度：**A**。建议考试用时 **75 分钟**，完整学习与复盘 **140 分钟**。

一个无序 JSON catalog 同时描述 primary 与 DR fleet。你需要把 fleet 编译为稳定的 `name@location`，再把容量编译为稳定的 `name@location#NN` replica。Grader 会在 LocalStack 两个 region 中创建 subnet 并注册 AMI，候选 state 只管理 IAM、Launch Template 和 EC2。

## 任务

只修改 `starter/`：

1. 严格验证 catalog 顶层 schema、精确字段集合、唯一 fleet、必需的 primary/DR 项、name/location/release、容量、instance type 与 64 位 artifact digest。
2. 以 `name@location` 建立 fleet map，以两位补零的 `#NN` 建立 replica map；catalog 重排不得改变地址，capacity 增长只能追加尾部地址。
3. Default provider 与 `aws.dr` 必须显式传入两个 regional module；provider 只暴露 LocalStack `ec2/iam/sts` endpoint，使用字面量 `test/test` 和三项 skip flag。
4. Root 只创建 IAM role/profile。Child 只允许 `data.aws_subnet`，subnet 与 image ID 均由 grader 注入；禁止候选创建或发现 VPC，也禁止 `data.aws_ami`。
5. 每个 replica 创建一个 `aws_launch_template` 与一个 `aws_instance`。LT user data、LT 的 instance tag specification 和 EC2 tags 必须携带 fleet、replica、release 与 digest 的完整追踪信息；EC2 直接镜像注入的 AMI、instance type 与 subnet，避免依赖 LocalStack 不稳定的 LT 关联回读。
6. 使用官方 `replace_triggered_by = [aws_launch_template.replica[each.key]]`：release/digest 改变时替换对应实例；纯 capacity 增长不能替换既有实例。
7. 输出排序后的 fleet/replica keys，以及按区域组织的 subnet、VPC、image、LT 和 instance 合同。

## 精确变更合同

- v1 saved plan：IAM role/profile、两份 LT、两台 EC2，共 **6 个 create**。
- v1 重排：严格 **0 变更**。
- v2：primary LT 原地 update 并只替换 primary `#01`；DR 旧 `#01` 保留，只新增 DR `#02` 的 LT 与 EC2，共 **4 个非 no-op 地址**。
- 单个 DR instance 的 Name tag 漂移：只允许该实例一个原地 update。
- v2 saved destroy：精确删除 **8 个 managed resources**，随后 IAM、LT、EC2 零残留。

## 边界

Terraform `~> 1.6`，最终验收固定使用 **1.6.6**；AWS provider `~> 5.100`。禁止 `terraform_data`、mock/override、SNS、候选 VPC、VPC/subnet 列表/AMI 发现、候选脚本与 `ignore_changes`。Canonical suite 恰好 10 个普通 Terraform 1.6.6 runs。

```powershell
$env:PATH = "$env:TEMP\tfpro-terraform-1.6.6;$env:PATH"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1 -UnitOnly
```
