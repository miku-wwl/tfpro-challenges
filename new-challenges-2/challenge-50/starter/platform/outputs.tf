output "platform_contract" {
  value = {
    contract_version = 1
    producer_run_id  = var.run_id
    release_version  = local.manifest.release_version
    bucket_name      = aws_s3_bucket.release.bucket
    artifact = {
      name   = local.artifact.name
      key    = aws_s3_object.bootstrap.key
      arn    = "${aws_s3_bucket.release.arn}/${aws_s3_object.bootstrap.key}"
      sha256 = local.artifact.sha256
    }
    identity_fingerprint = sha256(jsonencode(local.identity))
  }

  precondition {
    condition     = local.aggregate_valid
    error_message = "Invalid platform publication contract."
  }
}
