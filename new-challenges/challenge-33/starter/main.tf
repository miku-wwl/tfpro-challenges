# TODO: 解析 CSV，并以稳定 key 构造 active_services。
# TODO: 用显式 var.environment 建立 dev/stage/prod 环境合同和 checks/output precondition。
# TODO: 为每个启用服务创建 environment-specific S3 bucket 与 S3 release marker。

locals {
  active_services = {}
}
