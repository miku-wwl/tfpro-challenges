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

variable "release" {
  description = "自动化流程必须显式提供的发布版本。"
  type        = string

  validation {
    condition     = contains(["v1", "v2"], var.release)
    error_message = "release 只能是 v1 或 v2。"
  }
}

resource "aws_s3_bucket" "release" {
  bucket        = "tfpro-challenge74-release"
  force_destroy = true

  tags = {
    Challenge = "74"
  }
}

resource "aws_s3_object" "manifest" {
  bucket  = aws_s3_bucket.release.id
  key     = "release.txt"
  content = var.release
  etag    = md5(var.release)
}

output "release_contract" {
  description = "应用 saved plan 后可核验的发布合同。"
  value = {
    bucket  = aws_s3_bucket.release.id
    key     = aws_s3_object.manifest.key
    release = var.release
  }
}
