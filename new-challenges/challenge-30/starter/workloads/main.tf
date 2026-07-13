data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "${path.module}/${var.foundation_state_path}"
  }
}

data "terraform_remote_state" "platform" {
  backend = "local"
  config = {
    path = "${path.module}/${var.platform_state_path}"
  }
}

locals {
  rows = csvdecode(file("${path.module}/${var.catalog_file}"))
  selected = {
    for row in local.rows : trimspace(row.name) => {
      name        = trimspace(row.name)
      owner       = trimspace(row.owner)
      environment = trimspace(row.environment)
      locations   = split("|", trimspace(row.locations))
      port        = tonumber(row.port)
      enabled     = tobool(row.enabled)
    } if trimspace(row.environment) == var.target_environment && tobool(row.enabled)
  }
  # TODO: Row indexes and only the first location are not a stable expanded identity.
  deployments = {
    for index, row in local.rows : tostring(index) => {
      name        = trimspace(row.name)
      owner       = trimspace(row.owner)
      environment = trimspace(row.environment)
      locations   = split("|", trimspace(row.locations))
      location    = split("|", trimspace(row.locations))[0]
      port        = tonumber(row.port)
      enabled     = tobool(row.enabled)
    } if trimspace(row.environment) == var.target_environment && tobool(row.enabled)
  }
  primary_deployments = {
    for key, deployment in local.deployments : key => deployment if deployment.location == "primary"
  }
  dr_deployments = {
    for key, deployment in local.deployments : key => deployment if deployment.location == "dr"
  }
  owners = sort(distinct([for deployment in values(local.deployments) : deployment.owner]))
  deployments_by_owner = {
    for owner in local.owners : owner => sort([
      for key, deployment in local.deployments : key if deployment.owner == owner
    ])
  }
  network  = data.terraform_remote_state.foundation.outputs.network_contract
  platform = data.terraform_remote_state.platform.outputs.platform_contract
}

resource "terraform_data" "contract_guard" {
  input = sha256(file("${path.module}/${var.catalog_file}"))

  lifecycle {
    # TODO: Reject invalid/duplicate locations, unsupported upstream contract
    # versions, and contract/provider region mismatches.
    precondition {
      condition     = length(local.deployments) >= 0
      error_message = "Complete the catalog and upstream contract guard."
    }
  }
}

module "primary" {
  source    = "./modules/regional"
  providers = { aws = aws }

  run_id            = var.run_id
  role              = "primary"
  deployments       = local.primary_deployments
  network_contract  = local.network.primary
  platform_contract = local.platform.primary
}

module "dr" {
  source = "./modules/regional"
  # TODO: DR is incorrectly routed through primary.
  providers = { aws = aws }

  run_id            = var.run_id
  role              = "dr"
  deployments       = local.dr_deployments
  network_contract  = local.network.dr
  platform_contract = local.platform.dr
}
