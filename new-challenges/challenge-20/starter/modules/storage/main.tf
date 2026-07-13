resource "aws_s3_bucket" "this" {
  provider      = aws.target
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    ManagedBy = "terraform"
    Role      = var.role
  }
}

