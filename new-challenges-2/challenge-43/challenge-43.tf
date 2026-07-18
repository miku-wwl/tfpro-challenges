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

variable "bucket_name" {
  type    = string
  default = "tfpro-c43-interface"
}

variable "release_label" {
  type    = string
  default = "v1"
}

resource "aws_s3_bucket" "release" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name      = var.bucket_name
    Challenge = "43"
    Release   = var.release_label
  }
}

output "bucket_name" {
  description = "Legacy output retained during the interface refactor."
  value       = aws_s3_bucket.release.bucket
}
