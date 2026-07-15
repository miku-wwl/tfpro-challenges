output "release_contract" {
  value = {
    schema_version       = local.raw_catalog.schema_version
    release              = local.raw_catalog.release
    account_id           = data.aws_caller_identity.current.account_id
    bucket_name          = aws_s3_bucket.artifacts.bucket
    semantic_fingerprint = local.semantic_fingerprint
    object_addresses     = sort([for name in keys(local.artifacts_by_name) : "aws_s3_object.artifact[\"${name}\"]"])
    artifacts            = local.semantic_artifacts
  }

  precondition {
    condition     = local.catalog_valid
    error_message = "The release contract cannot be emitted for an invalid catalog."
  }
}
