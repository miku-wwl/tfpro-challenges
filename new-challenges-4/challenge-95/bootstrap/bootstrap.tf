terraform {
  required_version = "~> 1.6.0"

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

resource "aws_s3_bucket" "state" {
  bucket        = "tfpro-c95-state"
  force_destroy = true

  tags = {
    Challenge = "95"
    State     = "workspace-backend"
  }
}

output "state_bucket" {
  description = "Bucket that stores the dev and prod workspace states."
  value       = aws_s3_bucket.state.id
}
