variables {
  run_id        = "fixture01"
  manifest_path = "fixtures/release.json"
}

run "foundation_contract" {
  command = plan
  assert {
    condition     = output.foundation_contract.generation == 7 && output.foundation_contract.artifact_sha256 == "0094eec37cc9364a5d4e2e821f7c35c55c9182facc119795b91a51bd1648486e"
    error_message = "foundation release contract invalid."
  }
}

run "manifest_key_reorder_is_stable" {
  command = plan
  variables { manifest_path = "fixtures/release-reordered.json" }
  assert {
    condition     = output.foundation_contract.contract_id == "b6a93c4e71b3b7cc1f930208cb71872ee5825ac09ed70345a63f1e36e2c05580"
    error_message = "manifest reorder changed contract."
  }
}

run "nested_schema_is_rejected" {
  command = plan
  variables { manifest_path = "fixtures/release-bad-schema.json" }
  expect_failures = [check.schema_contract, output.catalog_guard]
}

run "bad_generation_key_and_hash_are_rejected" {
  command = plan
  variables { manifest_path = "fixtures/release-bad-hash.json" }
  expect_failures = [check.semantic_contract, output.catalog_guard]
}

run "unsafe_foundation_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "http://example.com:4566" }
  expect_failures = [var.localstack_endpoint]
}
