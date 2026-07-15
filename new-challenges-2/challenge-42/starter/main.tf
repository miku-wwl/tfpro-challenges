locals {
  routes_path = abspath("${path.root}/${var.routes_path}")
  catalog     = try(jsondecode(file(local.routes_path)), {})
  rows        = try(tolist(local.catalog.routes), [])

  # TODO 1: normalize the route catalog without losing duplicate detection.
  routes = {}
}

# TODO 2: add independent schema, unique-name, exact-field, and exact-three-slot checks.
check "route_contract" {
  assert {
    condition     = false
    error_message = "Complete the route compiler and checks."
  }
}

module "routed_storage" {
  source = "./modules/routed_storage"
  providers = {
    # TODO 3: map all three child slots to the matching root aliases.
    aws       = aws.primary
    aws.dr    = aws.primary
    aws.audit = aws.primary
  }

  routes = local.routes
  run_id = var.run_id
}
