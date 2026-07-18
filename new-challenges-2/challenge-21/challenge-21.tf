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
  buckets = {
    primary = "tfpro-c21-address-move"
  }
}

resource "aws_s3_bucket" "legacy" {
  for_each = local.buckets

  bucket        = each.value
  force_destroy = true

  tags = {
    Name      = each.value
    Challenge = "21"
    Key       = each.key
  }
}

output "bucket_contract" {
  description = "Physical identity must remain stable while the Terraform address changes."
  value = {
    key    = "primary"
    bucket = aws_s3_bucket.legacy["primary"].id
  }
}
