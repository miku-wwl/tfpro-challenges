data "terraform_remote_state" "identity" {
  backend = "s3"
  config = {
    bucket                      = var.state_bucket
    key                         = var.identity_state_key
    region                      = var.primary_region
    access_key                  = "test"
    secret_key                  = "test"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    endpoints = {
      s3 = var.localstack_endpoint
    }
  }
}

data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket                      = var.state_bucket
    key                         = var.platform_state_key
    region                      = var.primary_region
    access_key                  = "test"
    secret_key                  = "test"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    endpoints = {
      s3 = var.localstack_endpoint
    }
  }
}

locals {
  identity = try(data.terraform_remote_state.identity.outputs.identity_contract, {})
  platform = try(data.terraform_remote_state.platform.outputs.platform_contract, {})
  raw      = try(jsondecode(file("${path.module}/${var.catalog_path}")), {})
  rows     = try(local.raw.fleets, [])

  normalized = try([
    for row in local.rows : {
      name          = lower(trimspace(row.name))
      location      = lower(trimspace(row.location))
      instance_type = trimspace(row.instance_type)
      capacity      = row.capacity
      fields        = sort(keys(row))
      key           = "${lower(trimspace(row.name))}@${lower(trimspace(row.location))}"
    }
  ], [])

  groups = { for row in local.normalized : row.key => row... }
  catalog_valid = try(
    toset(keys(local.raw)) == toset(["fleets", "schema_version"]) &&
    local.raw.schema_version == 1 &&
    length(local.normalized) == 2 &&
    alltrue([
      for row in local.normalized :
      toset(row.fields) == toset(["capacity", "instance_type", "location", "name"]) &&
      can(regex("^[a-z][a-z0-9-]{2,15}$", row.name)) &&
      contains(["primary", "dr"], row.location) &&
      contains(["t3.micro", "t3.small"], row.instance_type) &&
      row.capacity == 1
    ]) &&
    alltrue([for _, group in local.groups : length(group) == 1]) &&
    toset(keys(local.groups)) == toset(["api@primary", "worker@dr"]),
    false
  )

  contract_valid = try(
    local.identity.contract_version == 1 &&
    local.identity.producer_run_id == var.run_id &&
    local.identity.role_name == "tfpro-c50-${var.run_id}" &&
    can(regex("^tfpro-c50-[a-z0-9-]+$", local.identity.instance_profile_name)) &&
    can(regex("^arn:aws:iam::[0-9]{12}:policy/tfpro-c50-[a-z0-9-]+$", local.identity.policy_arn)) &&
    can(regex("^[0-9a-f]{64}$", local.identity.policy_sha256)) &&
    local.platform.contract_version == 1 &&
    local.platform.producer_run_id == var.run_id &&
    local.platform.release_version == var.expected_release &&
    local.platform.bucket_name == "tfpro-c50-release-${var.run_id}" &&
    local.platform.identity_fingerprint == sha256(jsonencode(local.identity)) &&
    can(regex("^arn:aws:s3:::tfpro-c50-release-[a-z0-9-]+/releases/bootstrap\\.txt$", local.platform.artifact.arn)) &&
    can(regex("^[0-9a-f]{64}$", local.platform.artifact.sha256)),
    false
  )

  # TODO: combine both remote contracts, the catalog, and dual-region invariants.
  aggregate_valid = false
  # TODO: compile the validated groups into stable name@location identities.
  fleets  = {}
  primary = { for key, fleet in local.fleets : key => fleet if fleet.location == "primary" }
  dr      = { for key, fleet in local.fleets : key => fleet if fleet.location == "dr" }
}

module "primary" {
  source                = "./modules/regional"
  providers             = { aws = aws }
  fleets                = local.primary
  location              = "primary"
  region                = var.primary_region
  run_id                = var.run_id
  subnet_id             = var.primary_subnet_id
  image_id              = var.primary_image_id
  instance_profile_name = local.identity.instance_profile_name
  platform_contract     = local.platform
}

module "dr" {
  source = "./modules/regional"
  # TODO: route this module through the DR provider alias.
  providers             = { aws = aws }
  fleets                = local.dr
  location              = "dr"
  region                = var.dr_region
  run_id                = var.run_id
  subnet_id             = var.dr_subnet_id
  image_id              = var.dr_image_id
  instance_profile_name = local.identity.instance_profile_name
  platform_contract     = local.platform
}
