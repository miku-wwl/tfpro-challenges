output "revision_identity" {
  value = "${var.config_version}:${local.digest}"
}

output "bucket_name" {
  value = aws_s3_bucket.config.id
}

output "object_key" {
  value = aws_s3_object.config.key
}

output "table_name" {
  value = aws_dynamodb_table.config.name
}

