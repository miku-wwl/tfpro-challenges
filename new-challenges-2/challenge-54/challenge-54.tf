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

variable "release" {
  description = "Release marker stored independently in each CLI workspace state."
  type        = string
  default     = "v1"
}

resource "aws_s3_bucket" "environment" {
  bucket        = format("tfpro-c54-%s", terraform.workspace)
  force_destroy = true

  tags = {
    Challenge = "54"
    Workspace = terraform.workspace
    Release   = var.release
  }
}

output "workspace_contract" {
  value = {
    workspace = terraform.workspace
    bucket    = aws_s3_bucket.environment.id
    release   = aws_s3_bucket.environment.tags["Release"]
  }
}

# Task 2 adds a guard that prevents deployment from the default workspace.
