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
    iam = "http://localhost:4566"
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variable "bucket_names" {
  description = "Buckets that the completed reader policy is allowed to access."
  type        = set(string)
  default = [
    "tfpro-c63-artifacts",
    "tfpro-c63-logs",
  ]
}

variable "role_name" {
  description = "Name of the LocalStack IAM role created in Task 4."
  type        = string
  default     = "tfpro-c63-reader"
}

resource "aws_s3_bucket" "scoped" {
  for_each = var.bucket_names

  bucket        = each.value
  force_destroy = true

  tags = {
    ManagedBy = "Terraform"
    Challenge = "63"
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_arns = sort([for bucket in values(aws_s3_bucket.scoped) : bucket.arn])
  object_arns = sort([for bucket in values(aws_s3_bucket.scoped) : "${bucket.arn}/*"])
}

# Tasks 2 and 3 add two aws_iam_policy_document data sources: one trust
# document and one least-privilege permissions document.
#
# Task 4 then adds aws_iam_role, aws_iam_policy, and
# aws_iam_role_policy_attachment resources. They are intentionally absent from
# this starter so that the baseline manages only the two S3 buckets.

output "caller_account_id" {
  description = "Account used when constructing and checking the IAM contract."
  value       = data.aws_caller_identity.current.account_id
}

output "bucket_scope" {
  description = "Sorted bucket and object ARN inputs for the policy document tasks."
  value = {
    buckets = local.bucket_arns
    objects = local.object_arns
  }
}

# Task 5 adds a decoded policy-contract output and a wildcard safety check.
