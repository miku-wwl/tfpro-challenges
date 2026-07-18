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

variable "bucket_contract" {
  description = "A typed but not yet validated contract. Add the required safeguards during the lab."
  type = object({
    name        = string
    environment = string
    owner       = string
  })

  default = {
    name        = "tfpro-c26-dev-validated"
    environment = "dev"
    owner       = "platform"
  }
}

variable "expected_account_id" {
  description = "Expected LocalStack account ID for the non-blocking check exercise."
  type        = string
  default     = "000000000000"
}

locals {
  bucket_name = lower(trimspace(var.bucket_contract.name))
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "validated" {
  bucket = local.bucket_name

  tags = {
    Name        = local.bucket_name
    Challenge   = "26"
    Environment = var.bucket_contract.environment
    Owner       = var.bucket_contract.owner
  }
}

output "validation_baseline" {
  description = "The final lab adds variable, resource, and global validation around this contract."
  value = {
    bucket      = aws_s3_bucket.validated.id
    environment = var.bucket_contract.environment
    owner       = var.bucket_contract.owner
    account_id  = data.aws_caller_identity.current.account_id
  }
}
