terraform {

  backend "s3" {
    region = "us-east-1"

    endpoints = {
      dynamodb = "http://localhost:4566"
      s3       = "http://localhost:4566"
    }

    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
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
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variable "release" {
  description = "用于制造可审阅变更并保持锁的发布版本。"
  type        = string

  validation {
    condition     = contains(["v1", "v2"], var.release)
    error_message = "release 只能是 v1 或 v2。"
  }
}

resource "aws_s3_bucket" "application" {
  bucket        = "tfpro-challenge73-application"
  force_destroy = true

  tags = {
    Challenge = "73"
    Release   = var.release
  }
}

output "application_release" {
  description = "当前 state 管理的应用发布版本。"
  value = {
    bucket  = aws_s3_bucket.application.id
    release = var.release
  }
}
