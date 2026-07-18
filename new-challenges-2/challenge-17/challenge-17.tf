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

resource "aws_s3_bucket" "release" {
  bucket        = "tfpro-c17-saved-plan"
  force_destroy = true

  tags = {
    Name      = "tfpro-c17-saved-plan"
    Challenge = "17"
    Release   = "v1"
  }
}

output "release_contract" {
  description = "The release recorded by the applied plan and Terraform state."
  value = {
    bucket  = aws_s3_bucket.release.id
    release = aws_s3_bucket.release.tags["Release"]
  }
}
