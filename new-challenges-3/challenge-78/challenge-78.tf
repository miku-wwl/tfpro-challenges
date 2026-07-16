terraform {
  required_version = "~> 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

locals {
  releases = {
    blue = {
      bucket_name = "tfpro-challenge78-blue"
    }
    green = {
      bucket_name = "tfpro-challenge78-green"
    }
  }
}

# This call intentionally uses for_each with a legacy child module that owns
# its provider configuration. Task 1 begins by reading the resulting error.
module "release" {
  source   = "./modules/release"
  for_each = local.releases

  bucket_name = each.value.bucket_name
}

output "release_buckets" {
  value = {
    for name, release in module.release : name => release.bucket_id
  }
}
