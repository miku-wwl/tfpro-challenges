terraform {
  required_version = "~> 1.6.0"

  backend "s3" {
    region = "us-east-1"

    endpoints = {
      s3 = "http://localhost:4566"
    }

    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true

    # bucket and key are partial settings supplied during terraform init.
    # Backend credentials must never be added to this source block.
  }

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

resource "aws_s3_bucket" "release" {
  bucket        = "tfpro-c94-release"
  force_destroy = true

  tags = {
    Challenge = "94"
    State     = "remote"
  }
}

output "workload_contract" {
  description = "Resource managed by the remote state under audit."
  value = {
    bucket_name = aws_s3_bucket.release.id
    bucket_arn  = aws_s3_bucket.release.arn
  }
}
