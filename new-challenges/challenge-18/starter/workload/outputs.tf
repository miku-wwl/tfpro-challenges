output "deployment_keys" {
  value = sort(keys(module.service_primary))
}

output "deployment_addresses" {
  value = [
    for key in sort(keys(module.service_primary)) :
    "module.service_primary[\"${key}\"].aws_security_group.service"
  ]
}

# TODO: Group selected deployment keys by owner and sort every list.
output "deployments_by_owner" {
  value = {}
}

