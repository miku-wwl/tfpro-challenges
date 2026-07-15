module "primary" {
  source = "./modules/regional-bucket"

  # TODO 1: explicitly map aws.primary into the child default aws slot.
  providers = { aws = aws.dr }
  role      = "primary"
  region    = var.primary_region
  bucket    = "${var.name_prefix}-primary"
}

module "dr" {
  source = "./modules/regional-bucket"

  # TODO 2: explicitly map aws.dr into the child default aws slot.
  providers = { aws = aws.primary }
  role      = "dr"
  region    = var.dr_region
  bucket    = "${var.name_prefix}-dr"
}

check "regions_differ" {
  assert {
    condition     = var.primary_region != var.dr_region
    error_message = "primary_region and dr_region must differ."
  }
}
