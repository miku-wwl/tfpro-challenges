# TODO: 解析 CSV，并以稳定 key 构造 active_services。
# TODO: 用 terraform.workspace 建立 dev/stage/prod 环境合同和输入 preconditions。
# TODO: 为每个启用服务创建 workspace-specific S3 bucket 与 SNS topic。

locals {
  active_services = {}
}
