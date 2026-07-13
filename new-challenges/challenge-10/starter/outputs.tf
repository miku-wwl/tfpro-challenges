output "service_ports" {
  value = { for service in module.service : service.name => service.port }
}

output "healthcheck_paths" {
  value = { for service in module.service : service.name => service.healthcheck }
}

output "module_contract_versions" {
  value = { for service in module.service : service.name => service.contract_version }
}

output "resource_addresses" {
  # TODO: v2 必须输出具名 module 地址。
  value = [for index in range(length(module.service)) : "module.service[${index}].terraform_data.this"]
}
