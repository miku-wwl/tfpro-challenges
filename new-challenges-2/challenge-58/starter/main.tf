locals {
  catalog_path   = abspath("${path.root}/${var.catalog_path}")
  raw_catalog    = try(jsondecode(file(local.catalog_path)), {})
  raw_identities = try(local.raw_catalog.identities, [])

  # Keep both static import targets addressable while the compiler is built.
  fallback_identities = {
    api    = { name = "api", owner = "platform", actions = ["s3:GetObject"] }
    worker = { name = "worker", owner = "delivery", actions = ["s3:GetObject"] }
  }

  # TODO 1: normalize the strict directory, preserve duplicate/action evidence,
  # and replace this fallback only when every independent contract is valid.
  compiled_identities = local.fallback_identities
}

# TODO 2: replace this placeholder with independent schema, directory, shape,
# identity, and action checks.
check "catalog_contract" {
  assert {
    condition     = length(local.raw_identities) < 0
    error_message = "Complete the identity compiler and independent checks."
  }
}

module "identity" {
  source   = "./modules/identity"
  for_each = local.compiled_identities

  run_id   = var.run_id
  identity = each.value
}
