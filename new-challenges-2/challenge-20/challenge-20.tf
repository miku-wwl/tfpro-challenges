terraform {
  required_version = ">= 1.6.0, < 2.0.0"

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
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

locals {
  bucket_name = "tfpro-c20-imported"
  bucket_tags = {
    Name      = "tfpro-c20-imported"
    Challenge = "20"
    Owner     = "TerraformImport"
  }
}

output "starter_import_target" {
  description = "The desired identity to use for both the CLI-created object and import."
  value = {
    bucket = local.bucket_name
    tags   = local.bucket_tags
  }
}
