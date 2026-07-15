output "catalog_guard" {
  value = local.catalog_valid
  precondition {
    condition     = local.catalog_valid
    error_message = "catalog is invalid."
  }
}

# TODO(4): output release, service/node keys, exact addresses, IDs, and real LT bindings.
output "fleet_contract" {
  value = {
    release_version = try(local.raw.release_version, "TODO")
    services        = sort(keys(local.services))
    nodes           = sort(keys(local.nodes))
  }
}
