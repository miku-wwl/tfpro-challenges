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
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Intentional runtime fault for Task 1: LocalStack listens on 4566.
  endpoints {
    s3  = "http://localhost:4567"
    sts = "http://localhost:4567"
  }
}

data "aws_caller_identity" "probe" {}

resource "aws_s3_bucket" "diagnostic" {
  bucket        = "tfpro-c51-provider-diagnostic"
  force_destroy = true

  tags = {
    Challenge = "51"
    Purpose   = "runtime-diagnostics"
  }
}

output "diagnostic_contract" {
  value = {
    account_id = data.aws_caller_identity.probe.account_id
    bucket     = aws_s3_bucket.diagnostic.id
  }
}
