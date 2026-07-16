# Task 2 turns this reusable leaf into a module that requires one explicit
# provider slot named aws.deployment.

variable "bucket_name" {
  description = "Bucket managed through the provider supplied by the caller."
  type        = string
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Challenge = "92"
    Layer     = "leaf"
  }
}

output "bucket_name" {
  description = "Physical bucket ID."
  value       = aws_s3_bucket.this.id
}
