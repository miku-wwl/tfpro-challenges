terraform {
  required_version = "~> 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

# The starter has one default provider, so both nested release modules inherit
# it. Tasks 2-4 replace this with two explicit aliases passed through every
# module boundary.
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = "http://localhost:4566"
  }
}

module "catalog" {
  source = "./modules/catalog"

  primary_bucket_name = "tfpro-c92-primary"
  audit_bucket_name   = "tfpro-c92-audit"

  # Task 4 maps the two root aliases to the middle module's two slots.
}

output "release_buckets" {
  description = "Physical IDs that must remain unchanged during provider refactoring."
  value       = module.catalog.bucket_names
}
