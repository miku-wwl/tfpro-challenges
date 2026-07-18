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

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

data "aws_caller_identity" "primary" {}

resource "aws_s3_bucket" "primary" {
  bucket        = "tfpro-c47-primary"
  force_destroy = true

  tags = {
    Challenge  = "47"
    RegionRole = "primary"
  }
}

output "primary_contract" {
  value = {
    account_id = data.aws_caller_identity.primary.account_id
    bucket     = aws_s3_bucket.primary.id
    region     = "us-east-1"
  }
}

# Tasks add a complete aws.dr provider alias, a routed data source,
# a second bucket, and a combined routing_contract output.
