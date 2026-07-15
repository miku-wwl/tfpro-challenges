output "receipt_contract" {
  value = {
    bucket_name = aws_s3_bucket.receipts.bucket
    object_keys = { for name, object in aws_s3_object.receipt : name => object.key }
  }
}
