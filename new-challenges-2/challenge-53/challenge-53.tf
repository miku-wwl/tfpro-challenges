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

variable "release_token" {
  description = "Deliberately sensitive input used to audit plan and state boundaries."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.release_token) >= 12
    error_message = "release_token must contain at least 12 characters."
  }
}

resource "aws_s3_bucket" "audit" {
  bucket        = "tfpro-c53-sensitive-audit"
  force_destroy = true

  tags = {
    Challenge = "53"
    Purpose   = "sensitive-boundary"
  }
}

# This starter is intentionally unsafe: marking a value sensitive hides normal
# CLI rendering but does not prevent the object content from entering state.
resource "aws_s3_object" "unsafe_manifest" {
  bucket = aws_s3_bucket.audit.id
  key    = "release/manifest.json"
  content = jsonencode({
    release = "v1"
    token   = var.release_token
  })
}

output "manifest" {
  sensitive = true
  value = {
    bucket = aws_s3_bucket.audit.id
    key    = aws_s3_object.unsafe_manifest.key
    token  = var.release_token
  }
}
