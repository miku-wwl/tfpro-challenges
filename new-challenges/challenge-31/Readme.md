# Challenge 31：CSV 驱动的 EC2 计算舰队

**难度：96 / 100（Terraform Professional = 100）**  
**建议时间：120 分钟**

平台团队把计算舰队写在 CSV 中。你需要将弱类型表格转换成稳定的 Terraform graph，并同时处理 AWS data source、launch template、实例扩展与容量合同。

完成 `starter/`：

1. 严格校验 `environment`、网络对象、CSV 路径以及 loopback LocalStack endpoint。
2. 标准化 CSV 中的布尔值和数字；仅选择目标环境且 `enabled=true` 的记录。
3. `fleet_id` 必须是 launch template 与 security group 的唯一 `for_each` key；实例必须使用 `fleet_id/ordinal` 复合 key。CSV 重排不能改变地址。
4. 使用 `data.aws_ami` 选择可用镜像，并用 `data.aws_vpc`、`data.aws_subnet` 回读真实网络。
5. 用显式 `check` 拒绝重复 ID、非法容量关系、未知 subnet、非法布尔值以及空 owner/instance type。
6. 每个 launch template 必须连接正确的 SG、AMI 与 instance type；`aws_instance` 必须引用 launch template 的 `$Latest` 版本、对应 subnet，并按 `desired_capacity` 展开。
7. 输出稳定排序的 fleet IDs、resource addresses 与容量合同。
8. 所有本题 AWS 资源都必须带 `RunId = var.run_id`，以支持 grader 的精确清理。

Canonical tests 精确包含 11 个 run，覆盖正常输入、CSV 重排、非法环境、重复 ID、容量越界、未知 subnet、不存在的 CSV、非 loopback endpoint、非法 enabled、空 owner/type 与非法 network。

grader 会在真实 LocalStack 中创建 1 个 VPC、2 个 subnet、2 个 security group、2 个 launch template 与 3 个 EC2 instance，随后验证远端属性、clean plan、destroy 与零残留。LocalStack Community 创建实例后不会回读其 launch-template 来源，并会把 launch template 顶层 tags 回读成额外 tag specification；你需要用窄范围 `ignore_changes` 消除这两项模拟器噪声，并以 `terraform_data` revision sentinel 配合 `replace_triggered_by` 保留模板变更触发实例替换的语义。

```powershell
pwsh ./tmp2/challenge-31/tests/grade.ps1
```

fixtures 是只读输入合同。禁止真实 AWS 凭证、非本机 endpoint、行号 key 或吞掉失败的检查。
