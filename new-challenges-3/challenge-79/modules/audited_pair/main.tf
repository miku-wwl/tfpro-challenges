terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "primary_bucket_name" {
  type = string
}

variable "audit_bucket_name" {
  type = string
}

resource "aws_s3_bucket" "primary" {
  bucket        = var.primary_bucket_name
  force_destroy = true

  tags = {
    Challenge = "79"
    Slot      = "primary"
  }
}

resource "aws_s3_bucket" "audit" {
  bucket        = var.audit_bucket_name
  force_destroy = true

  tags = {
    Challenge = "79"
    Slot      = "audit"
  }
}

output "bucket_names" {
  value = {
    primary = aws_s3_bucket.primary.id
    audit   = aws_s3_bucket.audit.id
  }
}
