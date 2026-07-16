module "replicated_storage" {
  source = "./modules/replicated-storage"

  providers = {
    aws.primary  = aws.primary
    aws.recovery = aws.recovery
  }

  name_prefix     = var.name_prefix
  primary_region  = var.primary_region
  recovery_region = var.recovery_region
  common_tags     = var.common_tags
}

check "regions_differ" {
  assert {
    condition     = var.primary_region != var.recovery_region
    error_message = "recovery_region must differ from primary_region."
  }
}

