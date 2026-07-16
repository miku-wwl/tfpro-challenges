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

# 锁表由 README 中的 AWS CLI 命令创建，不能在本配置中添加 aws_dynamodb_table。
resource "aws_s3_bucket" "state" {
  bucket        = "tfpro-challenge73-state"
  force_destroy = true

  tags = {
    Challenge = "73"
    Purpose   = "terraform-state"
  }
}

output "state_bucket" {
  description = "App 的远端 state Bucket。"
  value       = aws_s3_bucket.state.id
}
