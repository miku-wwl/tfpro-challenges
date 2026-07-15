locals {
  catalog_path   = abspath("${path.root}/${var.catalog_path}")
  raw_catalog    = try(jsondecode(file(local.catalog_path)), {})
  schema_version = try(tonumber(local.raw_catalog.schema_version), 0)
  raw_bundles    = try(tolist(local.raw_catalog.bundles), [])

  # TODO 1: validate both interface versions and normalize them into one typed
  # child-module contract without losing duplicate/action detection.
  bundles = {}
}

# TODO 2: replace this placeholder with independent checks for top-level schema,
# exact v1/v2 shapes, semantic identities, artifact integrity, and IAM actions.
check "interface_contract" {
  assert {
    condition     = length(local.raw_bundles) < 0
    error_message = "Complete the interface compiler and all contract checks."
  }
}

module "release_bundle" {
  source   = "./modules/release_bundle"
  for_each = local.bundles

  run_id   = var.run_id
  name     = each.key
  owner    = each.value.owner
  contract = each.value.contract
}
