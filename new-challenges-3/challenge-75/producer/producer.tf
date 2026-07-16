terraform {

  backend "s3" {
    region = "us-east-1"

    endpoints = {
      s3 = "http://localhost:4566"
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

locals {
  # Task 5 会把发布版本从 v1 推进到 v2。
  release = "v1"
  manifest_body = jsonencode({
    application = "payments"
    release     = local.release
  })
}

resource "aws_s3_bucket" "release" {
  bucket        = "tfpro-challenge75-release"
  force_destroy = true

  tags = {
    Challenge = "75"
    Owner     = "producer"
  }
}

resource "aws_s3_object" "manifest" {
  bucket  = aws_s3_bucket.release.id
  key     = "manifest.json"
  content = local.manifest_body
  etag    = md5(local.manifest_body)
}

output "release_contract" {
  description = "Consumer 唯一允许读取的跨配置合同。"
  value = {
    schema_version = 1
    release        = local.release
    bucket         = aws_s3_bucket.release.id
    object_key     = aws_s3_object.manifest.key
    payload_sha256 = sha256(local.manifest_body)
  }
}
