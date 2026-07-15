output "catalog_guard" {
  value = local.catalog_valid
  precondition {
    condition     = local.catalog_valid
    error_message = "release invalid."
  }
}
# TODO: output every scalar foundation contract field and recomputable contract_id.
