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

resource "aws_s3_bucket" "active" {
  bucket        = "tfpro-c19-active"
  force_destroy = true

  tags = {
    Name      = "tfpro-c19-active"
    Challenge = "19"
    Lifecycle = "active"
  }
}

resource "aws_s3_bucket" "legacy" {
  bucket        = "tfpro-c19-legacy"
  force_destroy = true

  tags = {
    Name      = "tfpro-c19-legacy"
    Challenge = "19"
    Lifecycle = "retire"
  }
}

output "active_bucket" {
  description = "The bucket that must survive the targeted retirement."
  value       = aws_s3_bucket.active.id
}
