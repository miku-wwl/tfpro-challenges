run "v1_contract_is_complete" {
  command = plan
  assert {
    condition = (
      output.artifact_contract.contract_version == 1 &&
      output.artifact_contract.producer_run_id == var.run_id &&
      output.artifact_contract.revision == "2026.07.1" &&
      toset(keys(output.artifact_contract.artifacts)) == toset(["api", "worker"]) &&
      output.artifact_contract.artifacts.api.content_sha256 == sha256("api artifact v1") &&
      output.artifact_contract.artifacts.worker.content_sha256 == sha256("worker artifact v1") &&
      can(regex("^[0-9a-f]{64}$", output.artifact_contract.fingerprint))
    )
    error_message = "The publisher contract is incomplete."
  }
}

run "catalog_reorder_is_semantically_stable" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-v1-reordered.json" }
  assert {
    condition     = output.artifact_contract.artifacts.api.key == "releases/api.txt" && output.artifact_contract.artifacts.worker.key == "releases/worker.txt"
    error_message = "Catalog order changed stable artifact identity."
  }
}

run "v2_preserves_artifact_keys" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-v2.json" }
  assert {
    condition     = output.artifact_contract.revision == "2026.07.2" && toset(keys(output.artifact_contract.artifacts)) == toset(["api", "worker"])
    error_message = "The v2 publication changed stable artifact keys."
  }
}

run "duplicate_name_is_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-duplicate-name.json" }
  expect_failures = [aws_s3_bucket.artifacts]
}

run "duplicate_key_is_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-duplicate-key.json" }
  expect_failures = [aws_s3_bucket.artifacts]
}

run "invalid_top_level_shape_is_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-invalid-top-shape.json" }
  expect_failures = [aws_s3_bucket.artifacts]
}

run "invalid_record_shape_is_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-invalid-record-shape.json" }
  expect_failures = [aws_s3_bucket.artifacts]
}

run "invalid_revision_key_owner_and_content_are_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-invalid-semantics.json" }
  expect_failures = [aws_s3_bucket.artifacts]
}

run "public_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com:443" }
  expect_failures = [var.localstack_endpoint]
}

run "invalid_run_id_is_rejected" {
  command = plan
  variables { run_id = "BAD" }
  expect_failures = [var.run_id]
}
