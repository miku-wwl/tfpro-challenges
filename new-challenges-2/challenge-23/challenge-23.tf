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
    s3 = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "exercise" {
  bucket = "tfpro-c23-drift"

  tags = {
    Name        = "tfpro-c23-drift"
    Challenge   = "23"
    Environment = "managed"
    Owner       = "terraform"
  }
}

output "bucket_contract" {
  description = "The configured contract used to compare configuration, state, and the API."
  value = {
    id   = aws_s3_bucket.exercise.id
    tags = aws_s3_bucket.exercise.tags
  }
}
