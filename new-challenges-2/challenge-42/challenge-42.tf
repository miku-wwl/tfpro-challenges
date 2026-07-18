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

variable "deployments" {
  type = map(object({
    bucket_name = string
    owner       = string
  }))

  default = {
    blue = {
      bucket_name = "tfpro-c42-blue"
      owner       = "platform-team"
    }
    green = {
      bucket_name = "tfpro-c42-green"
      owner       = "platform-team"
    }
  }
}

resource "aws_s3_bucket" "blue" {
  bucket        = var.deployments["blue"].bucket_name
  force_destroy = true

  tags = {
    Name      = var.deployments["blue"].bucket_name
    Challenge = "42"
    Owner     = var.deployments["blue"].owner
  }
}

resource "aws_s3_bucket" "green" {
  bucket        = var.deployments["green"].bucket_name
  force_destroy = true

  tags = {
    Name      = var.deployments["green"].bucket_name
    Challenge = "42"
    Owner     = var.deployments["green"].owner
  }
}

output "starter_deployments" {
  value = {
    blue = {
      name = aws_s3_bucket.blue.bucket
      arn  = aws_s3_bucket.blue.arn
    }
    green = {
      name = aws_s3_bucket.green.bucket
      arn  = aws_s3_bucket.green.arn
    }
  }
}
