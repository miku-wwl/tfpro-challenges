locals {
  primary_bucket_name = "${var.name_prefix}-primary"
  dr_bucket_name      = "${var.name_prefix}-dr"
}

module "primary" {
  source = "./modules/regional_stack"

  providers = {
    aws.target = aws.primary
  }

  name_prefix     = var.name_prefix
  role            = "primary"
  expected_region = var.primary_region
  peer_bucket     = local.dr_bucket_name
}

module "dr" {
  source = "./modules/regional_stack"

  # TODO: 灾备 module 不能复用 primary provider。
  providers = {
    aws.target = aws.primary
  }

  name_prefix     = var.name_prefix
  role            = "dr"
  expected_region = var.dr_region
  peer_bucket     = local.dr_bucket_name
}

