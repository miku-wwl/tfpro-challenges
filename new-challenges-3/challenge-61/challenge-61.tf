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
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variable "bucket_spec" {
  description = "Starter specification. Add the requested validation rules during the challenge."

  type = object({
    name          = string
    environment   = string
    force_destroy = bool
    tags          = map(string)
  })

  default = {
    name          = "tfpro-c61-dev-guardrails"
    environment   = "dev"
    force_destroy = true
    tags = {
      Owner = "platform-team"
    }
  }

  # Task 2: add input validation here. The starter intentionally accepts
  # values that should be rejected by the completed configuration.
}

data "aws_caller_identity" "current" {}

locals {
  bucket_tags = merge(
    {
      Environment = var.bucket_spec.environment
      ManagedBy   = "Terraform"
    },
    var.bucket_spec.tags,
  )
}

resource "aws_s3_bucket" "guarded" {
  bucket        = var.bucket_spec.name
  force_destroy = var.bucket_spec.force_destroy
  tags          = local.bucket_tags

  # Tasks 3 and 4 add lifecycle preconditions and postconditions. They are
  # absent from the starter so that you can observe the unguarded baseline.
}

output "bucket_contract" {
  description = "Small root-module contract used by the verification steps."
  value = {
    name        = aws_s3_bucket.guarded.bucket
    arn         = aws_s3_bucket.guarded.arn
    environment = var.bucket_spec.environment
  }
}

output "caller_account_id" {
  description = "The LocalStack account observed through the AWS provider."
  value       = data.aws_caller_identity.current.account_id
}

# Task 5 adds a top-level check block. Do not add test files or provider mocks.
