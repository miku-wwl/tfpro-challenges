# Challenge 14：版本约束、Lockfile 与模块接口升级

## 场景

发布清单 root 当前使用 v1 本地模块和 Random provider 3.6 patch line。平台标准要求升级到 v2 模块；v2 把输入/输出接口改成 typed manifest，并要求 Random provider 3.7。你还收到两个失败现场：root/child provider 约束无交集，以及 lockfile 选择与新约束不一致。

Random provider 只生成本地随机 ID，不访问云服务，不需要凭证。

## 任务

只修改 `starter/`：

1. 保持 Terraform binary 约束为 `~> 1.6`（允许受支持的 Terraform 1.x，拒绝 2.x）。
2. 把 Random provider 约束升级为 `~> 3.7.0`，与 v2 child module 的 `>= 3.7.0` 形成非空交集。
3. 把 module source 切换到 `fixtures/modules/release-v2`，按新接口传入 `service_name` 和 `release_channels`。
4. 消费 v2 的 `manifest`，用 resource pre/postconditions 固定 `schema_version = 2` 和 artifact 集合合同。
5. 执行 `terraform init -upgrade`，生成/更新 `.terraform.lock.hcl`；随后证明 `terraform init -lockfile=readonly` 可重复成功。
6. 修复输出并通过测试。
7. 阅读 `fixtures/failures/` 两个现场，在 `DIAGNOSIS.md` 中解释根因、定位命令和安全修复。保留三个验收标记字符串。

推荐诊断命令：

```powershell
terraform -chdir=tmp2/challenge-14/starter providers
terraform -chdir=tmp2/challenge-14/starter init -upgrade -input=false
terraform -chdir=tmp2/challenge-14/starter init -lockfile=readonly -input=false
terraform -chdir=tmp2/challenge-14/starter providers schema -json
```

## 验收

```powershell
pwsh -NoProfile -File tmp2/challenge-14/tests/grade.ps1 -Candidate tmp2/challenge-14/starter
```

grader 会验证 fmt/init/validate/test、3.7.x lock selection、readonly init、v2 manifest，以及两个失败现场确实以预期方式失败。

## 不变量

- root 与所有 child module 的 provider 约束取交集；不能只看 root。
- `.terraform.lock.hcl` 记录最终选择和校验哈希，应该随配置交付；`.terraform/` 不应交付。
- 普通 `init` 尊重既有选择；有意升级才使用 `init -upgrade`。
- module source 变化必须同步处理输入/输出接口，不能靠 `try(..., null)` 静默兼容错误版本。
- `-lockfile=readonly` 不得修改 lockfile，且必须成功。

## 安全边界

- 不连接云，不使用凭证；随机值不代表秘密。
- 不删除 lockfile 来“修复”故障；先解释约束交集和选择变化，再执行明确升级。
- failure fixtures 是只读案例；grader 在临时副本运行它们。

## Terraform Professional objective

覆盖 Professional 大纲中的 Terraform/provider/module 版本管理、child module provider requirements、dependency lockfile、`init -upgrade`、可重复初始化和系统化故障定位。
