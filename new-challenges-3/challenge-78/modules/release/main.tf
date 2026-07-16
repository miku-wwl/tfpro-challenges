terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Legacy pattern for this exercise: provider configurations do not belong in
# reusable child modules. Move this block to the root module in Task 2.
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

variable "bucket_name" {
  description = "Name of one release bucket."
  type        = string
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Challenge = "78"
  }
}

output "bucket_id" {
  value = aws_s3_bucket.this.id
}
