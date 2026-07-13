locals {
  config_raw = file(var.config_path)
  config     = jsondecode(local.config_raw)
  digest     = sha256(local.config_raw)
}

# TODO: 添加配置合同 check 和 terraform_data.config_revision。

resource "aws_s3_bucket" "config" {
  bucket = "${var.name_prefix}-${var.environment}-config"

  # TODO: 保护关键 bucket，禁止普通 destroy。
}

resource "aws_dynamodb_table" "config" {
  name         = "${var.name_prefix}-${var.environment}-config"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ConfigKey"

  attribute {
    name = "ConfigKey"
    type = "S"
  }
}

resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.config.id
  key          = "config/current.json"
  content      = local.config_raw
  content_type = "application/json"

  # TODO: replace_triggered_by、precondition、postcondition。
}

# TODO: 创建与 S3 版本/摘要一致的 aws_dynamodb_table_item。

