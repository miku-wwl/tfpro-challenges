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
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variable "enable_audit" {
  description = "Whether the optional audit bucket exists."
  type        = bool
  default     = true
}

resource "aws_s3_bucket" "audit" {
  count = var.enable_audit ? 1 : 0

  bucket        = "tfpro-challenge86-audit"
  force_destroy = true

  tags = {
    Challenge = "86"
    Purpose   = "optional-audit"
  }
}

# The default baseline is runnable, but this direct index is unsafe when
# enable_audit=false. Task 3 replaces it with one(full-splat).
output "audit_contract" {
  description = "Keep this object shape stable while bucket becomes string or null."
  value = {
    enabled = var.enable_audit
    bucket  = aws_s3_bucket.audit[0].id
  }
}
