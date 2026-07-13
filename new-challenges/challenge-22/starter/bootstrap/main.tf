resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # TODO: 最终 bootstrap destroy 必须能精确清理 state objects。
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"

  # TODO: S3 backend 的 DynamoDB locking 合同要求字符串 LockID。
  hash_key = "LockId"
  attribute {
    name = "LockId"
    type = "S"
  }
}
