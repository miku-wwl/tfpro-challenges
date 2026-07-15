output "legacy_addresses" {
  value = concat(
    [for item in terraform_data.service : item.id],
    [local_file.manifest.id]
  )
}

