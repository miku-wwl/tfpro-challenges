output "name" {
  value = var.name
}

output "port" {
  value = var.port
}

output "healthcheck" {
  # TODO: v2 必须透传 optional healthcheck。
  value = null
}

output "contract_version" {
  # TODO: 完成 v2 interface 后更新版本。
  value = 1
}
