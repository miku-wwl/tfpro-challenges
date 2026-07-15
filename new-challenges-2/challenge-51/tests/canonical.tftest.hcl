variables { catalog_path = "fixtures/takeover.json" }
run "takeover_contract" {
  command = plan
  assert {
    condition     = output.takeover_contract.contract_version == 1 && output.takeover_contract.workload == "api" && length(output.takeover_contract.addresses) == 3
    error_message = "takeover contract invalid."
  }
}
run "reordered_catalog_is_stable" {
  command = plan
  variables { catalog_path = "fixtures/takeover-reordered.json" }
  assert {
    condition     = output.takeover_contract.workload == "api" && output.takeover_contract.instance_type == "t3.micro"
    error_message = "reorder changed contract."
  }
}
run "bad_schema_is_rejected" {
  command = plan
  variables { catalog_path = "fixtures/takeover-bad-schema.json" }
  expect_failures = [check.schema_contract, output.catalog_guard]
}
run "bad_version_is_rejected" {
  command = plan
  variables { catalog_path = "fixtures/takeover-bad-version.json" }
  expect_failures = [check.semantic_contract, output.catalog_guard]
}
run "invalid_fields_are_rejected" {
  command = plan
  variables { catalog_path = "fixtures/takeover-invalid-fields.json" }
  expect_failures = [check.semantic_contract, output.catalog_guard]
}
run "unsafe_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "http://example.com:4566" }
  expect_failures = [var.localstack_endpoint]
}
