terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "bucket_name" {
  description = "Name of the team's release bucket."
  type        = string
}

variable "owner" {
  description = "Team that owns the release bucket."
  type        = string
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Challenge = "77"
    Owner     = var.owner
  }
}

output "bucket_id" {
  value = aws_s3_bucket.this.id
}
