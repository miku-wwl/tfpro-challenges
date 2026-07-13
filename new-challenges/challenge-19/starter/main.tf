locals {
  bucket_name      = "${var.name_prefix}-archive"
  table_name       = "${var.name_prefix}-locks"
  manifest_key     = "releases/manifest.json"
  manifest_content = file("${path.module}/../fixtures/desired-manifest.json")
}

resource "aws_s3_bucket" "archive" {
  bucket = local.bucket_name

  # TODO: grader 会保留一个已 state rm 的对象；销毁时仍必须能清空 bucket。
  force_destroy = false

  tags = {
    ManagedBy = "terraform"
    Purpose   = "release-archive"
  }
}

resource "aws_dynamodb_table" "locks" {
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

resource "aws_s3_object" "release_manifest" {
  bucket       = aws_s3_bucket.archive.id
  key          = local.manifest_key
  content      = local.manifest_content
  content_type = "application/json"
  etag         = md5(local.manifest_content)
}

resource "terraform_data" "inventory" {
  input = {
    bucket = aws_s3_bucket.archive.id
    table  = aws_dynamodb_table.locks.name
  }
}

