[CmdletBinding()]
param(
  [ValidateSet("Deploy", "Destroy")]
  [string]$Action,
  [string]$Root,
  [string]$StateBucket,
  [string]$LockTable,
  [string]$StatePrefix,
  [string]$LocalstackEndpoint = "http://localhost:4566",
  [string]$ReleaseId = "v2"
)

$ErrorActionPreference = "Stop"

# TODO: 生成两个 backend config；Deploy 必须 plan -out 后 apply plan，
# Destroy 必须先 consumer 后 producer，并写 .runtime/destroy-order.log。
throw "release automation 尚未实现"
