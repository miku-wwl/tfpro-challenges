terraform {

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

# This is the starter's complete default provider. Task 2 adds alias =
# "primary", intentionally leaving Terraform with no explicit default.
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

provider "aws" {
  alias                       = "audit"
  region                      = "us-west-2"
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

data "aws_caller_identity" "primary" {
  # Task 3 binds this data source to aws.primary.
}

data "aws_caller_identity" "audit" {
  provider = aws.audit
}

resource "aws_s3_bucket" "primary" {
  # Task 3 binds this resource to aws.primary.
  bucket        = "tfpro-c93-primary"
  force_destroy = true

  tags = {
    Challenge = "93"
    Route     = "primary"
  }
}

resource "aws_s3_bucket" "audit" {
  provider      = aws.audit
  bucket        = "tfpro-c93-audit"
  force_destroy = true

  tags = {
    Challenge = "93"
    Route     = "audit"
  }
}

output "routing_contract" {
  description = "Both aliases reach LocalStack, while state preserves their distinct provider addresses."
  value = {
    primary = {
      bucket     = aws_s3_bucket.primary.id
      account_id = data.aws_caller_identity.primary.account_id
    }
    audit = {
      bucket     = aws_s3_bucket.audit.id
      account_id = data.aws_caller_identity.audit.account_id
    }
  }
}
