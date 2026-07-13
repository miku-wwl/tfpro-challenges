output "service_keys" {
  value = sort(keys(terraform_data.service))
}

output "services_by_owner" {
  value = local.services_by_owner
}

output "manifest_path" {
  value = local_file.manifest.filename
}

output "manifest_checksum" {
  value = local_file.manifest.content_sha256
}

output "guardian_id" {
  value = terraform_data.guardian.id
}

