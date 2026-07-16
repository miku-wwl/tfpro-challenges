# The starter deliberately relies on Terraform's implicit hashicorp/aws
# requirement. Task 3 replaces that inference with an explicit terraform block.

variable "bucket_name" {
  description = "Name of the LocalStack release bucket."
  type        = string
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Challenge = "91"
    Purpose   = "provider-requirements"
  }
}

output "bucket_name" {
  description = "Physical bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Physical bucket ARN."
  value       = aws_s3_bucket.this.arn
}
