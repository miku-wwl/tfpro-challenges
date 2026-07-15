data "terraform_remote_state" "foundation" {
  backend = "s3"
  # TODO 4: configure isolated LocalStack S3 remote state from variables.
  config = {}
}

locals {
  rows = csvdecode(file(var.catalog_file))
  # TODO 5: normalize/filter rows, expand location=both, and key by service@location.
  deployments = {}
  primary     = {}
  dr          = {}
}

check "service_contract" {
  assert {
    condition     = length(local.deployments) > 0
    error_message = "Selected services must have unique names and valid owner, tier, port, enabled, and location fields."
  }
}

module "service_primary" {
  for_each  = local.primary
  source    = "./modules/service"
  providers = { aws = aws.primary }
  # TODO 6: pass the primary remote-state contract and normalized service object.
  bucket_name             = "unknown"
  environment             = var.target_environment
  location                = "primary"
  platform_schema_version = 0
  service                 = each.value
}

module "service_dr" {
  for_each  = local.dr
  source    = "./modules/service"
  providers = { aws = aws.dr }
  # TODO 7: pass the DR remote-state contract and normalized service object.
  bucket_name             = "unknown"
  environment             = var.target_environment
  location                = "dr"
  platform_schema_version = 0
  service                 = each.value
}
