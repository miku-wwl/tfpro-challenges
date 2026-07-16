output "service_keys" {
  value = sort(keys(terraform_data.service))
}

output "service_profiles" {
  value = {
    for key, resource in terraform_data.service : key => resource.input
  }
}

output "services_by_owner" {
  value = {
    for owner in distinct([
      for service in values(local.services) : service.owner
    ]) :
    owner => sort([
      for name, service in local.services :
      name if service.owner == owner
    ])
  }
}

output "deployment_tokens" {
  value = {
    for name, service in local.services :
    name => sha256(join(":", [
      var.token_salt,
      name,
      local.owners[service.owner].token_seed
    ]))
  }

  sensitive = true
}