data "terraform_remote_state" "foundation" {
  backend = "s3"

  # TODO: complete the Terraform 1.6 LocalStack S3 remote-state config.
  config = {
    bucket = var.state_bucket
    key    = var.foundation_state_key
    region = var.primary_region
  }
}

locals {
  platform_contract = data.terraform_remote_state.foundation.outputs.platform_contract
  rows              = csvdecode(file("${path.module}/${var.catalog_file}"))

  # TODO: normalize/filter/expand location=both into application@location stable keys.
  deployments         = {}
  primary_deployments = {}
  dr_deployments      = {}
}

# TODO: call two static application modules and route aws.primary/aws.dr explicitly.
