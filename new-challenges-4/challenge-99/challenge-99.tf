terraform {
  required_version = "~> 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

locals {
  releases = {
    dev = {
      bucket_name = "tfpro-c99-dev"
      serial      = 1
    }
    prod = {
      bucket_name = "tfpro-c99-prod"
      serial      = 1
    }
  }

  artifacts = {
    "api.zip"    = "api"
    "worker.zip" = "worker"
  }
}

module "release" {
  for_each = local.releases
  source   = "./modules/release"

  environment = each.key
  bucket_name = each.value.bucket_name
  serial      = each.value.serial
  artifacts   = local.artifacts
}

output "release_contracts" {
  value = {
    for environment, release in module.release : environment => release.contract
  }
}
