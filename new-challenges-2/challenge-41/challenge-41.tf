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
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

variable "release" {
  type = object({
    bucket_name   = string
    release       = string
    force_destroy = bool
  })

  default = {
    bucket_name   = "tfpro-c41-release"
    release       = "v1"
    force_destroy = true
  }
}

resource "aws_s3_bucket" "release" {
  bucket        = var.release.bucket_name
  force_destroy = var.release.force_destroy

  tags = {
    Name      = var.release.bucket_name
    Challenge = "41"
    Release   = var.release.release
  }
}

resource "aws_s3_object" "manifest" {
  bucket       = aws_s3_bucket.release.id
  key          = "release/manifest.json"
  content_type = "application/json"
  content = jsonencode({
    release = var.release.release
  })
}

output "release_contract" {
  value = {
    name         = aws_s3_bucket.release.bucket
    arn          = aws_s3_bucket.release.arn
    release      = var.release.release
    manifest_key = aws_s3_object.manifest.key
  }
}
