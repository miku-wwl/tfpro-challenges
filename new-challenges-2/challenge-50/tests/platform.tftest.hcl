run "v1_remote_identity_drives_release" {
  command = plan
  assert {
    condition = (
      output.platform_contract.contract_version == 1 &&
      output.platform_contract.producer_run_id == var.run_id &&
      output.platform_contract.release_version == "2026.07.1" &&
      output.platform_contract.bucket_name == "tfpro-c50-release-${var.run_id}" &&
      output.platform_contract.artifact.key == "releases/bootstrap.txt" &&
      output.platform_contract.artifact.sha256 == "4eddb29d73949015731e6bc64cdf99ef0670627f70003dd8e7a09e6748945e76" &&
      can(regex("^[0-9a-f]{64}$", output.platform_contract.identity_fingerprint))
    )
    error_message = "The v1 platform contract is incomplete."
  }
}

run "v2_preserves_artifact_identity" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-v2.json" }
  assert {
    condition = (
      output.platform_contract.release_version == "2026.07.2" &&
      output.platform_contract.artifact.key == "releases/bootstrap.txt" &&
      output.platform_contract.artifact.sha256 == "5bc85795367dc5ba369f5ec157b4ea4ece3274462b37c9379730f2310365bca0"
    )
    error_message = "The v2 release changed stable artifact identity or omitted its digest."
  }
}

run "bad_payload_digest_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-bad-digest.json" }
  expect_failures = [aws_s3_bucket.release]
}

run "bad_manifest_schema_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-bad-schema.json" }
  expect_failures = [aws_s3_bucket.release]
}

run "unsafe_artifact_key_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-unsafe-key.json" }
  expect_failures = [aws_s3_bucket.release]
}

run "wrong_identity_state_key_is_rejected" {
  command = plan
  variables { identity_state_key = "wrong/terraform.tfstate" }
  expect_failures = [var.identity_state_key]
}

run "public_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com:443" }
  expect_failures = [var.localstack_endpoint]
}
