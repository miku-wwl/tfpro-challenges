terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "bucket_name" {
  description = "Name of the artifact bucket."
  type        = string
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Challenge = "76"
    Purpose   = "artifact-storage"
  }
}

# Task 2: publish a typed bucket contract from this module.
