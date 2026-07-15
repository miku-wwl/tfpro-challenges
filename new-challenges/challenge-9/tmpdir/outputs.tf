output "legacy_addresses" {
  value = concat(
    [for item in terraform_data.workload : item.id],
    [terraform_data.retired.id, local_file.inventory.id]
  )
}

