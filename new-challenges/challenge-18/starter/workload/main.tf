data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = var.foundation_state_path
  }
}

locals {
  catalog_rows = csvdecode(file("${path.module}/${var.catalog_file}"))

  services = [
    for row in local.catalog_rows : {
      name        = trimspace(row.service)
      owner       = trimspace(row.owner)
      environment = trimspace(row.environment)
      port        = tonumber(row.port)
      enabled     = tobool(row.enabled)
      location    = trimspace(row.location)
      tier        = trimspace(row.tier)
    }
  ]

  # TODO: Exclude disabled rows and build stable service@location keys.
  selected = {
    for index, service in local.services : tostring(index) => service
    if service.environment == var.target_environment
  }

  # TODO: Split primary, DR, and both-location services into static module calls.
  primary = local.selected
  dr      = {}
}

module "service_primary" {
  for_each = local.primary
  source   = "./modules/service"

  service        = each.value
  network        = data.terraform_remote_state.foundation.outputs.network_contract.primary
  deployment_key = each.key
}

# TODO: Instantiate DR services with providers = { aws = aws.dr }.

