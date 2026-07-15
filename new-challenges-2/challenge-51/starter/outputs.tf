output "catalog_guard" {
  value = local.catalog_valid

  precondition {
    condition     = local.catalog_valid
    error_message = "catalog is invalid."
  }
}
# TODO(5): publish the exact takeover contract and final addresses.
