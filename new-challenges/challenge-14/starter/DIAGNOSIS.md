# Failure diagnosis

## Provider constraint intersection

现场目录：`fixtures/failures/provider-conflict`

根因是 root 和 child module 对同一个 provider 的版本约束没有交集：

- root 要求 `random ~> 3.6.0`，即 `>= 3.6.0` 且 `< 3.7.0`；
- child 要求 `random >= 3.7.0`。

不存在同时满足这两个条件的版本，因此 `terraform init` 无法选择 provider release。

定位命令：

```powershell
terraform providers
terraform init
```

安全修复是先检查 root 和所有 child module 的约束交集，再调整 root 约束到兼容范围，
例如将 root 升级到 `~> 3.7.0`。不要通过删除 child 的版本约束来掩盖接口不兼容。

`ROOT_CHILD_CONSTRAINT_INTERSECTION`

## Stale lock selection

现场目录：`fixtures/failures/stale-lock`

`versions.tf` 已要求 `random ~> 3.7.0`，但 `.terraform.lock.hcl` 仍记录：

```text
version     = 3.6.3
constraints = ~> 3.6.0
```

旧 lock selection 不满足新的 provider 约束，因此只读初始化必须拒绝它。只读模式的目的
是验证 lockfile 是否已经正确，而不是替它修复版本选择。

定位命令：

```powershell
terraform providers
terraform init -lockfile=readonly
```

安全修复是先确认新的约束和升级意图，再执行：

```powershell
terraform init -upgrade
```

检查生成的 `.terraform.lock.hcl` 后，再验证：

```powershell
terraform init -lockfile=readonly
```

不应直接删除 lockfile，因为这样会丢失已审核的版本选择和校验哈希。

`LOCKFILE_SELECTION_CONFLICT`

## Module API

v1 child module 使用：

- 输入：`name` 和 `channels`；
- 输出：`legacy_release`，字段为 `name` 和 `ids`。

v2 child module 改为：

- 输入：`service_name` 和 `release_channels`；
- `service_name` 是小写 slug，并带有 validation；
- `release_channels` 是 `set(string)`，只允许 `canary` 和 `stable`；
- 输出：`manifest`，包含 `schema_version = 2`、`service_name` 和 `artifacts`。

root 应使用 v2 的 `module.release.manifest` 作为 contract 输入，并通过 resource
precondition 固定 schema version 为 2，再通过 postcondition 验证 artifact keys 与
`release_channels` 完全一致。这样可以在 module API 变化时尽早失败，而不是静默接受旧结构。

`MODULE_API_V2`
