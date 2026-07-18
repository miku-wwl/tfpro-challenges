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

variable "release_label" {
  type    = string
  default = "v1"
}

resource "aws_s3_bucket" "release" {
  bucket        = "tfpro-c40-release"
  force_destroy = true

  tags = {
    Name      = "tfpro-c40-release"
    Challenge = "40"
    Release   = var.release_label
  }
}

output "release_contract" {
  value = {
    contract_version = 1
    name             = aws_s3_bucket.release.bucket
    arn              = aws_s3_bucket.release.arn
    release_label    = var.release_label
  }
}
