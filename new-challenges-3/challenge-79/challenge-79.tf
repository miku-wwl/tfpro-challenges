terraform {

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

# Baseline: both child resources inherit this one default configuration.
# Tasks 2-4 replace it with two explicit root aliases and child slots.
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

module "audited_pair" {
  source = "./modules/audited_pair"

  primary_bucket_name = "tfpro-challenge79-primary"
  audit_bucket_name   = "tfpro-challenge79-audit"
}

output "bucket_names" {
  value = module.audited_pair.bucket_names
}
