terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70.0"
    }
  }
}

provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

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

resource "aws_s3_bucket" "release_artifact" {
  bucket        = "tfpro-c16-release-artifact"
  force_destroy = true

  tags = {
    Name        = "tfpro-c16-release-artifact"
    Challenge   = "16"
    Environment = "exam"
    ManagedBy   = "terraform"
  }
}

output "release_artifact" {
  description = "Identity of the release artifact bucket."
  value = {
    bucket = aws_s3_bucket.release_artifact.id
    arn    = aws_s3_bucket.release_artifact.arn
  }
}
