# Challenge 56：稳定随机分片与不可扰动 EC2 Canary 发布

难度：**95 / 100**；考试模式 **75 分钟**，首次完整学习 **130 分钟**。评级：**A**。

grader 在 LocalStack 外部建立一个 VPC 与两个 subnet，并使用 LocalStack 的预置 AMI 目录。候选把七字段 CSV 编译为
service-keyed fleet，通过官方 `random_integer` 为每个 fleet 在两个候选 subnet 中选择稳定 canary
位置，再创建 Security Group、Launch Template 与 EC2 instance。目录重排不得重新抽签；只有显式
提高 `placement_epoch` 才允许单个 fleet 重新放置。

只修改 `starter/`：

1. 严格规范化七字段 CSV，独立拒绝错误 schema、空目录、重复 fleet ID、非法布尔值/环境/字段、非法 instance type、未知或重复候选 subnet、非法 epoch。
2. `subnet_ids` 由 grader 注入；只用 `data.aws_subnet.selected` 回读网络。AMI 必须由 `data.aws_ami.selected` 按安全名称 pattern 查询，禁止硬编码 ID。
3. 每个启用且属于目标环境的 fleet 创建一个 `random_integer.placement`；`keepers` 只能包含稳定 fleet ID 与显式 `placement_epoch`。
4. 以 fleet ID 驱动 SG、LT、instance 的 `for_each`。instance 使用随机结果选择 subnet，并以真实 LT ID、epoch、owner 和 run ID 建立审计 tags。
5. CSV 重排必须 clean；`fleets-rotated.csv` 只能替换 `api` 的 random placement 与 instance，`worker` 地址和 ID 保持不变。
6. 输出排序 fleet keys、四类精确地址、AMI/VPC/subnet/LT/instance/placement 合同，并用 blocking precondition 阻断所有目录错误。
7. AWS provider 仅使用 loopback LocalStack `ec2,sts` endpoint、字面量 `test/test` 与三项 skip flags；candidate 只使用官方 Pro 清单资源。
8. grader 使用 Terraform 1.6.6 运行 13 个普通 tests，然后审计 saved-plan JSON、真实 AWS readback、reorder no-op、受控重新分片、tag drift、clean plan、destroy 与零残留。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/grade.ps1
```

对应大纲：**1b/1c/1d/1e、2a/2b/2c/2d/2e、3c、5b/5c**。
