terraform {

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

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "mirror_proof" {
  bucket        = "tfpro-c96-provider-mirror"
  force_destroy = true

  tags = {
    Challenge = "96"
    Purpose   = "provider-mirror-proof"
  }
}

output "mirror_contract" {
  description = "The infrastructure contract must stay unchanged across provider reinstallation."
  value = {
    bucket     = aws_s3_bucket.mirror_proof.id
    account_id = data.aws_caller_identity.current.account_id
  }
}
