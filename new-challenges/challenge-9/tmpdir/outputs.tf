output "legacy_addresses" {
  value = concat(
    [for item in terraform_data.service : item.id],
    [terraform_data.retired.id, local_file.inventory.id]
  )
}

