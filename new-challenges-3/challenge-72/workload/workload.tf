terraform {

  # Task 3：在这里添加 partial S3 backend；不要把 bucket、key 或凭证写死。

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

resource "aws_s3_bucket" "workload" {
  bucket        = "tfpro-challenge72-workload"
  force_destroy = true

  tags = {
    Challenge = "72"
    State     = "migrate-without-recreate"
  }
}

output "workload_bucket" {
  description = "迁移前后必须保持不变的 Workload Bucket ID。"
  value       = aws_s3_bucket.workload.id
}
