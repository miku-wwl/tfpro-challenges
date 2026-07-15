locals {
  catalog_path = abspath("${path.root}/${var.catalog_path}")
  raw_catalog  = try(jsondecode(file(local.catalog_path)), {})
  raw_releases = try(tolist(local.raw_catalog.releases), [])

  # TODO 3: normalize the strict catalog without losing duplicate detection,
  # then key the valid graph only by semantic release name.
  releases = {}
}

# TODO 4: replace this placeholder with independent schema, directory, shape,
# identity, content, and primary/replica region checks.
check "catalog_contract" {
  assert {
    condition     = length(local.raw_releases) < 0
    error_message = "Complete the release compiler and independent checks."
  }
}

module "release" {
  source   = "./modules/dual_release"
  for_each = local.releases

  providers = {
    aws.primary = aws.primary
    # TODO 5: map the replica child slot to the correct root alias.
    aws.replica = aws.primary
  }

  run_id  = var.run_id
  release = each.value
}
