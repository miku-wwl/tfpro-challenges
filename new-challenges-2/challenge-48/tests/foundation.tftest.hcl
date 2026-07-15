run "v1_artifact_contract_is_complete" {
  command = plan
  assert {
    condition = (
      output.artifact_contract.contract_version == 1 &&
      output.artifact_contract.revision == "v1" &&
      output.artifact_contract.producer_run_id == var.run_id &&
      toset(keys(output.artifact_contract.artifacts)) == toset(["api", "worker"]) &&
      output.artifact_contract.artifacts.api.key == "releases/api.txt"
    )
    error_message = "The v1 artifact contract is incomplete."
  }
}

run "artifact_reorder_is_stable" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-v1-reordered.json" }
  assert {
    condition     = output.artifact_contract.artifacts.api.content_sha256 == sha256("api contract v1") && output.artifact_contract.artifacts.worker.content_sha256 == sha256("worker contract v1")
    error_message = "Catalog reorder changed semantic artifact values."
  }
}

run "v2_retains_artifact_keys" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-v2.json" }
  assert {
    condition     = output.artifact_contract.revision == "v2" && toset(keys(output.artifact_contract.artifacts)) == toset(["api", "worker"])
    error_message = "v2 changed stable artifact identity."
  }
}

run "duplicate_artifact_is_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-duplicate.json" }
  expect_failures = [aws_s3_bucket.artifacts]
}

run "invalid_schema_is_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-invalid-schema.json" }
  expect_failures = [aws_s3_bucket.artifacts]
}

run "unsafe_key_is_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/artifacts-unsafe-key.json" }
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
