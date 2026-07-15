module "replicated_storage" {
  source = "./modules/replicated-storage"

  # TODO 1: route the two child provider slots to their matching root aliases.
  providers = {
    aws.primary  = aws.recovery
    aws.recovery = aws.primary
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

