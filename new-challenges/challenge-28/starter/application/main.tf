data "terraform_remote_state" "network" {
  backend = "local"
  config  = { path = var.network_state_path }
}

locals {
  rows = csvdecode(file("${path.module}/${var.catalog_file}"))
  applications = [for row in local.rows : {
    name        = trimspace(row.name)
    owner       = trimspace(row.owner)
    environment = trimspace(row.environment)
    port        = tonumber(row.port)
    enabled     = tobool(row.enabled)
    location    = trimspace(row.location)
  }]

  # TODO: Filter enabled rows, expand both, and key by application@location.
  selected = { for index, app in local.applications : tostring(index) => app if app.environment == var.target_environment }
  primary  = local.selected
  dr       = {}
}

resource "terraform_data" "contract_guard" {
  input = sha256(file("${path.module}/${var.catalog_file}"))

  lifecycle {
    # TODO: Reject invalid locations, duplicate expanded keys, incompatible
    # network contract versions, and provider/contract region mismatches.
    precondition {
      condition     = length(local.applications) >= 0
      error_message = "Complete the catalog and upstream contract guard."
    }
  }
}

module "application_primary" {
  for_each = local.primary
  source   = "./modules/application"
  providers = {
    aws = aws
  }
  run_id         = var.run_id
  deployment_key = each.key
  application    = each.value
  network        = data.terraform_remote_state.network.outputs.network_contract.primary
}

# TODO: Add a static DR module block mapped to aws.dr.
