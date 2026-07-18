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

resource "aws_s3_bucket" "governance_scenario" {
  bucket        = "tfpro-c59-governance-scenario"
  force_destroy = true

  # Owner is intentionally absent so the first plan violates the scenario policy.
  tags = {
    Challenge   = "59"
    Environment = "prod"
  }
}

output "governance_contract" {
  value = {
    bucket = aws_s3_bucket.governance_scenario.id
    tags   = aws_s3_bucket.governance_scenario.tags
  }
}
