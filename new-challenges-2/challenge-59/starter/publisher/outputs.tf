output "artifact_contract" {
  value = {
    contract_version = 1
    producer_run_id  = var.run_id
    revision         = local.raw_catalog.revision
    bucket_name      = local.bucket_name
    bucket_arn       = "arn:aws:s3:::${local.bucket_name}"
    artifacts        = local.contract_artifacts
    fingerprint      = "" # TODO: hash the exact canonical revision + artifacts contract.
  }
}
