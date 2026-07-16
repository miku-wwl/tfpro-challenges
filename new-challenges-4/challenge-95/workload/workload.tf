terraform {
  required_version = "~> 1.6.0"

  backend "s3" {
    region               = "us-east-1"
    workspace_key_prefix = "challenge95/environments"

    endpoints = {
      s3 = "http://localhost:4566"
    }

    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true

    # Task 2 supplies only bucket and key during init.
  }

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
    s3 = "http://localhost:4566"
  }
}

locals {
  allowed_workspaces = toset(["dev", "prod"])
  bucket_name        = "tfpro-c95-${terraform.workspace}-release"
}

resource "aws_s3_bucket" "release" {
  bucket        = local.bucket_name
  force_destroy = true

  lifecycle {
    precondition {
      condition     = contains(local.allowed_workspaces, terraform.workspace)
      error_message = "Deploy only from the dev or prod workspace; default is a control workspace."
    }
  }

  tags = {
    Challenge = "95"
    Workspace = terraform.workspace
  }
}

output "workspace_contract" {
  description = "Contract that must differ between dev and prod state."
  value = {
    workspace   = terraform.workspace
    bucket_name = aws_s3_bucket.release.id
  }
}
