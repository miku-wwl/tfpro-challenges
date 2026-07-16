terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "bucket_name" {
  description = "Bucket that receives the release object."
  type        = string
}

variable "object_key" {
  description = "Key used for the current release object."
  type        = string
}

variable "content" {
  description = "Release content to publish."
  type        = string
}

resource "aws_s3_object" "this" {
  bucket       = var.bucket_name
  key          = var.object_key
  content      = var.content
  content_type = "text/plain"
}

output "object_key" {
  description = "Key of the published object."
  value       = aws_s3_object.this.key
}
