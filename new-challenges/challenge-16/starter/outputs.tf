output "service_names" {
  # TODO: 输出排序后的业务名称，而不是 for_each key。
  value = sort(keys(local.services_by_key))
}

output "service_addresses" {
  value = sort([
    for key in keys(local.services_by_key) : "terraform_data.service[\"${key}\"]"
  ])
}

output "inventory_sha256" {
  value = sha256(local_file.inventory.content)
}

