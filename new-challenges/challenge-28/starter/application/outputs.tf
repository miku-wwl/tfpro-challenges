output "deployment_keys" {
  value = sort(keys(local.deployments))
  # TODO: add blocking contract/catalog preconditions.
}

output "regional_deployments" {
  # TODO: merge primary and DR module contracts.
  value = {}
}

output "deployments_by_owner" {
  # TODO: publish stable owner groups.
  value = {}
}
