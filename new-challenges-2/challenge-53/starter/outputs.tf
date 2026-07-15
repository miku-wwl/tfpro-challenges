output "catalog_guard" {
  value = local.catalog_valid
  precondition {
    condition     = local.catalog_valid
    error_message = "catalog invalid."
  }
}
# TODO(4): publish the exact dual-region ownership/address contract.
