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
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "contract" {
  bucket = "tfpro-c101-contract"

  tags = {
    Challenge = "101"
    ManagedBy = "Terraform"
  }
}

output "starter_bucket" {
  value = {
    arn  = aws_s3_bucket.contract.arn
    name = aws_s3_bucket.contract.id
  }
}
