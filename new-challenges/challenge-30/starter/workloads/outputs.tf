output "deployment_keys" {
  value = sort(keys(local.deployments))
}

output "deployment_contracts" {
  value = merge(module.primary.contracts, module.dr.contracts)
}

output "deployments_by_owner" {
  # TODO: Publish the sorted owner grouping contract.
  value = {}
}
