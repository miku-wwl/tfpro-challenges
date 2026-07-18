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

variable "storage_request" {
  type = object({
    environment      = string
    publish_manifest = optional(bool)
    force_destroy    = optional(bool)
    tags             = optional(map(string))
  })

  default = {
    environment = "dev"
  }
}

resource "aws_s3_bucket" "normalized" {
  bucket        = "tfpro-c33-normalization"
  force_destroy = true

  tags = {
    Name        = "tfpro-c33-normalization"
    Challenge   = "33"
    Environment = "dev"
  }
}

output "starter_storage" {
  value = {
    name        = aws_s3_bucket.normalized.bucket
    arn         = aws_s3_bucket.normalized.arn
    raw_request = var.storage_request
  }
}
