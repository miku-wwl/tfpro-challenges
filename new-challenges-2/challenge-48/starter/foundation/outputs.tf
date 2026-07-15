output "artifact_contract" {
  value = {
    contract_version = 1
    producer_run_id  = var.run_id
    revision         = local.raw_catalog.revision
    bucket_name      = aws_s3_bucket.artifacts.bucket
    bucket_arn       = aws_s3_bucket.artifacts.arn
    artifacts        = local.contract_artifacts
    fingerprint = sha256(jsonencode({
      revision  = local.raw_catalog.revision
      artifacts = local.contract_artifacts
    }))
  }
  precondition {
    condition     = local.catalog_valid
    error_message = "An invalid catalog cannot publish a remote-state contract."
  }
}
