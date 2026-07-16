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
    s3 = "http://localhost:4566"
  }
}

module "release" {
  source      = "./modules/release"
  bucket_name = "tfpro-c91-release"
}

output "release_contract" {
  description = "Root contract used to prove that provider-requirement edits do not replace infrastructure."
  value = {
    bucket_name = module.release.bucket_name
    bucket_arn  = module.release.bucket_arn
  }
}
