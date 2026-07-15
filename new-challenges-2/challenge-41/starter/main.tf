locals {
  catalog_path = abspath("${path.root}/${var.catalog_path}")
  catalog      = try(jsondecode(file(local.catalog_path)), {})
  rows         = try(tolist(local.catalog.services), [])

  # TODO 1: normalize rows, preserve duplicate detection, and key enabled services by semantic name.
  services = {}
}

# TODO 2: add five independent check blocks for schema, non-empty catalog,
# unique normalized names, exact valid fields, and at least one enabled service.
check "catalog_contract" {
  assert {
    condition     = false
    error_message = "Complete the independent catalog checks."
  }
}

module "service" {
  source   = "./modules/service"
  for_each = local.services

  run_id  = var.run_id
  service = each.value
}
