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

variable "bucket_name" {
  description = "Name used by the configuration and by temporary Terraform tests."
  type        = string
  default     = "tfpro-c52-test-baseline"

  validation {
    condition = (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      startswith(var.bucket_name, "tfpro-c52-") &&
      can(regex("^[a-z0-9-]+$", var.bucket_name))
    )
    error_message = "bucket_name must start with tfpro-c52- and use 3-63 lowercase letters, digits, or hyphens."
  }
}

resource "aws_s3_bucket" "under_test" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Challenge = "52"
    TestedBy  = "terraform-test"
  }
}

output "bucket_contract" {
  value = {
    name      = aws_s3_bucket.under_test.id
    arn       = aws_s3_bucket.under_test.arn
    challenge = aws_s3_bucket.under_test.tags["Challenge"]
  }
}
