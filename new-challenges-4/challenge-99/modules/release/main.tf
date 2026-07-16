terraform {
  required_version = "~> 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

variable "environment" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "serial" {
  type = number
}

variable "artifacts" {
  type = map(string)
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Challenge   = "99"
    Environment = var.environment
  }
}

resource "aws_s3_object" "artifact" {
  for_each = var.artifacts

  bucket       = aws_s3_bucket.this.id
  key          = "artifacts/${each.key}"
  content_type = "application/json"
  content = jsonencode({
    component   = each.value
    environment = var.environment
    serial      = var.serial
  })
}

output "contract" {
  value = {
    bucket = aws_s3_bucket.this.id
    serial = var.serial
    objects = {
      for key, object in aws_s3_object.artifact : key => object.key
    }
  }
}
