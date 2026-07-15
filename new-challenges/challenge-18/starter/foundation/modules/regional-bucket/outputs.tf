output "contract" {
  value = { bucket_name = aws_s3_bucket.this.bucket, region = var.region, account_id = data.aws_caller_identity.current.account_id }
}
