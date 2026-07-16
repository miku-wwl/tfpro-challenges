terraform {

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.80.0"
    }
  }
}

variable "name" {
  type = string
}

variable "tags" {
  type = map(string)
}

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = true
  tags          = var.tags
}

output "contract" {
  value = {
    name = aws_s3_bucket.this.id
    arn  = aws_s3_bucket.this.arn
  }
}
