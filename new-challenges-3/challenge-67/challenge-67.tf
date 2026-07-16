terraform {

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

variable "api_token" {
  description = "Fake lab token used to demonstrate Terraform state exposure."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.api_token) >= 12
    error_message = "api_token must contain at least 12 characters."
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "tfpro-challenge-67-${data.aws_caller_identity.current.account_id}"

  # Unsafe starter behavior: sensitive redacts display, but this raw value still
  # becomes part of the S3 object and Terraform state.
  receipt_body = jsonencode({
    challenge = 67
    token     = var.api_token
  })
}

resource "aws_s3_bucket" "audit" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Challenge = "67"
    Purpose   = "sensitive-state-audit"
  }
}

resource "aws_s3_object" "receipt" {
  bucket       = aws_s3_bucket.audit.id
  key          = "receipts/token.json"
  content      = local.receipt_body
  content_type = "application/json"
}

output "receipt_bucket" {
  value = aws_s3_bucket.audit.id
}

output "receipt_body" {
  value     = local.receipt_body
  sensitive = true
}
