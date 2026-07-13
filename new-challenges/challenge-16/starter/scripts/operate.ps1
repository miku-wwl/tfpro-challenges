param(
    [string]$Workspace = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"

# TODO: 实现 README 规定的 saved plan、JSON audit、state backup/restore、
# refresh-only drift 与 repair 流程。grader 要求最终写出：
#   .automation/evidence.json
# 切勿把 exit code 2 当成命令失败，也不要直接 apply 未审计配置。
throw "TODO: implement the audited Terraform automation workflow"

