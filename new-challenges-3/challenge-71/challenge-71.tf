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
    s3  = "http://localhost:4566"
    sts = "http://localhost:4566"
  }
}

resource "aws_s3_bucket" "artifact" {
  bucket        = "tfpro-challenge71-provider-lock"
  force_destroy = true

  tags = {
    Challenge = "71"
    Purpose   = "provider-lock"
  }
}

output "artifact_bucket" {
  description = "用于验证 Provider 初始化后可以正常访问 LocalStack 的 Bucket。"
  value       = aws_s3_bucket.artifact.id
}
