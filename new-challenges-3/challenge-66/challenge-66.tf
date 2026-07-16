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
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "tfpro-challenge-66-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "releases" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Challenge = "66"
    Purpose   = "destroy-intent"
  }
}

resource "aws_s3_object" "active" {
  bucket       = aws_s3_bucket.releases.id
  key          = "releases/current.txt"
  content      = "release-v2"
  content_type = "text/plain"
}

# This legacy object is intentionally still managed in the starter.
resource "aws_s3_object" "retired" {
  bucket       = aws_s3_bucket.releases.id
  key          = "releases/legacy.txt"
  content      = "release-v1"
  content_type = "text/plain"
}

output "release_contract" {
  value = {
    bucket     = aws_s3_bucket.releases.id
    active_key = aws_s3_object.active.key
  }
}
