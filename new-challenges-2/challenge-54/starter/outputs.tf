output "catalog_guard" {
  value = local.catalog_valid
  precondition {
    condition     = local.catalog_valid
    error_message = "policy contract invalid."
  }
}
# TODO(4): output public ownership and a sensitive digest-only receipt.
