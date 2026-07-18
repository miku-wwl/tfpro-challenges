terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70.0"
    }
  }
}

variable "release_targets" {
  description = "Release targets keyed by environment."
  type        = map(any)

  default = {
    dev = {
      bucket_name   = "tfpro-c16-dev-artifacts"
      environment   = "development"
      release       = "2026.07.18-dev"
      retention_days = 3
      extra_tags = {
        CostCentre = "engineering"
      }
    }

    prod = {
      bucket_name   = "tfpro-c16-production-artifacts"
      environment   = "prod"
      release       = ""
      retention_days = 120
      extra_tags = {
        CostCentre = "platform"
        Critical   = "true"
      }
    }
  }

  validation {
    condition     = length(var.release_targets) == 2
    error_message = "Exactly two release targets are required."
  }
}

locals {
  common_tags = {
    Challenge = "16"
    ManagedBy = "terraform"
  }
}

provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4567"
  }
}

provider "aws" {
  alias  = "audit"
  region = "us-east-1"

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

data "aws_caller_identity" "primary" {}

data "aws_caller_identity" "audit" {
  provider = aws.audit
}

resource "aws_s3_bucket" "release" {
  for_each = var.release_targets

  bucket        = each.value.bucket_name
  force_destroy = false

  tags = merge(each.value.extra_tags, local.common_tags, {
    Name          = each.value.bucket_name
    Environment   = each.key
    Release       = each.value.release
    RetentionDays = tostring(each.value.retention_days)
  })
}

resource "aws_s3_bucket_versioning" "release" {
  for_each = var.release_targets
  provider = aws.audit

  bucket = aws_s3_bucket.release["dev"].id

  versioning_configuration {
    status = each.key == "prod" ? "Suspended" : "Enabled"
  }
}

resource "aws_s3_object" "manifest" {
  for_each = var.release_targets
  provider = aws.audit

  bucket       = aws_s3_bucket.release[each.key].id
  key          = "manifest/${each.key}.json"
  content_type = "application/json"

  content = jsonencode({
    environment = each.key
    release     = each.value.release
  })
}

resource "aws_s3_object" "current" {
  for_each = var.release_targets
  provider = aws

  bucket       = aws_s3_bucket.release[each.key].id
  key          = "latest.txt"
  content_type = "text/plain"
  content      = each.value.release
}

check "provider_accounts_match" {
  assert {
    condition     = data.aws_caller_identity.primary.account_id == data.aws_caller_identity.audit.account_id
    error_message = "Primary and audit providers must address the same LocalStack account."
  }
}

output "release_inventory" {
  description = "Published release buckets and objects."

  value = {
    for environment, target in var.release_targets : environment => {
      bucket             = aws_s3_bucket.release[environment].bucket
      bucket_arn         = aws_s3_bucket.release[environment].arn
      versioning_status  = aws_s3_bucket_versioning.release[environment].versioning_configuration[0].status
      manifest_key       = aws_s3_object.manifest[environment].key
      current_key        = aws_s3_object.current[environment].key
      audit_account_id   = data.aws_caller_identity.audit.account_id
    }
  }
}
