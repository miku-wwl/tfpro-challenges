output "catalog_guard" {
  value = local.catalog_valid

  precondition {
    condition     = local.catalog_valid
    error_message = "catalog is invalid."
  }
}

# TODO(4): publish the sorted key, IDs, and address contract.
