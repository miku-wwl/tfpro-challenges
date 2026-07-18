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
  skip_region_validation      = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3 = "http://localhost:4566"
  }
}

variable "services" {
  description = "An ordered input list whose business codes must become stable Terraform instance keys."
  type = list(object({
    code    = string
    owner   = string
    enabled = bool
    payload = string
  }))

  default = [
    {
      code    = "api"
      owner   = "platform"
      enabled = true
      payload = "api-v1"
    },
    {
      code    = "worker"
      owner   = "operations"
      enabled = true
      payload = "worker-v1"
    },
    {
      code    = "retired"
      owner   = "archive"
      enabled = false
      payload = "disabled"
    }
  ]
}

resource "aws_s3_bucket" "services" {
  bucket = "tfpro-c29-stable-keys"

  tags = {
    Name      = "tfpro-c29-stable-keys"
    Challenge = "29"
  }
}

output "stable_key_starter" {
  description = "Tasks add validation, a keyed map, and one S3 object per enabled service."
  value = {
    bucket         = aws_s3_bucket.services.id
    supplied_codes = sort([for service in var.services : service.code])
  }
}
