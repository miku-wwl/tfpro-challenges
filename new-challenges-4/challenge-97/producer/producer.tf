terraform {
  required_version = "~> 1.6.0"

  backend "s3" {
    key                         = "challenge97/producer.tfstate"
    region                      = "us-east-1"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    endpoints = {
      s3 = "http://localhost:4566"
    }
  }

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

resource "aws_s3_bucket" "artifacts" {
  bucket        = "tfpro-c97-artifacts"
  force_destroy = true

  tags = {
    Challenge = "97"
    Owner     = "producer"
  }
}

output "release_contract" {
  description = "The stable v1 output already consumed by other configurations."
  value = {
    schema_version = 1
    bucket         = aws_s3_bucket.artifacts.id
    prefix         = "releases/"
  }
}

# Task 4 adds a new root output named retention_policy. It is intentionally
# absent in the starter so that the consumer first exercises its default.
