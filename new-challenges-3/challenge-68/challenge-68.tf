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
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

data "aws_caller_identity" "current" {}

locals {
  environments = {
    dev = {
      release = "dev-2026.07"
      owner   = "platform-dev"
    }
    prod = {
      release = "prod-2026.07"
      owner   = "platform-prod"
    }
  }

  workspace_supported = contains(keys(local.environments), terraform.workspace)
  environment = lookup(local.environments, terraform.workspace, {
    release = "unsupported"
    owner   = "unsupported"
  })
  bucket_name = "tfpro-challenge-68-${terraform.workspace}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "environment" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Challenge = "68"
    Workspace = terraform.workspace
    Owner     = local.environment.owner
  }

  lifecycle {
    precondition {
      condition     = local.workspace_supported
      error_message = "Select the dev or prod CLI workspace before planning."
    }
  }
}

resource "aws_s3_object" "release" {
  bucket = aws_s3_bucket.environment.id
  key    = "releases/current.json"
  content = jsonencode({
    workspace = terraform.workspace
    release   = local.environment.release
    owner     = local.environment.owner
  })
  content_type = "application/json"
}

output "workspace_contract" {
  value = {
    workspace = terraform.workspace
    bucket    = aws_s3_bucket.environment.id
    key       = aws_s3_object.release.key
    release   = local.environment.release
  }
}
