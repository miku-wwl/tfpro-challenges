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

resource "aws_s3_bucket" "managed" {
  bucket        = "tfpro-c22-managed"
  force_destroy = true

  tags = {
    Name      = "tfpro-c22-managed"
    Challenge = "22"
    Ownership = "terraform-state"
  }
}

output "managed_bucket" {
  description = "The identity used before state removal and after safe re-import."
  value = {
    bucket = aws_s3_bucket.managed.id
    arn    = aws_s3_bucket.managed.arn
  }
}
