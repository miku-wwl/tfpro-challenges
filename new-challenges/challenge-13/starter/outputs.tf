output "service_keys" {
  value = sort(keys(terraform_data.service))
}

output "service_profiles" {
  value = {
    for key, resource in terraform_data.service : key => resource.input
  }
}

output "services_by_owner" {
  # TODO: group and sort service keys by owner.
  value = {}
}

output "deployment_tokens" {
  # TODO: derive sha256 tokens from token_salt, stable service key, and owner seed.
  # Mark this output sensitive.
  value = {}
}
