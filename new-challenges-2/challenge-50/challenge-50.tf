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

resource "aws_s3_bucket" "release" {
  bucket        = "tfpro-c50-provider-upgrade"
  force_destroy = true

  tags = {
    Challenge = "50"
    Contract  = "stable-across-provider-upgrade"
  }
}

output "release_contract" {
  value = {
    bucket = aws_s3_bucket.release.id
    arn    = aws_s3_bucket.release.arn
  }
}
