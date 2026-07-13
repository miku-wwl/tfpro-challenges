locals {
  bucket_name = "${var.name_prefix}-archive"
  table_name  = "${var.name_prefix}-locks"
}

resource "aws_s3_bucket" "existing" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    ManagedBy = "terraform"
    Purpose   = "release-archive"
  }
}

resource "aws_dynamodb_table" "existing" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    ManagedBy = "terraform"
    Purpose   = "release-locks"
  }
}

