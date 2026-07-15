variables { catalog_path = "fixtures/regions.json" }

run "dual_region_contract" {
  command = plan
  assert {
    condition     = output.regional_contract.primary.instance_type == "t3.micro" && output.regional_contract.dr.instance_type == "t3.small" && length(output.regional_contract.addresses) == 6
    error_message = "dual-region contract invalid."
  }
}

run "region_reorder_is_stable" {
  command = plan
  variables { catalog_path = "fixtures/regions-reordered.json" }
  assert {
    condition     = output.regional_contract.primary.instance_type == "t3.micro" && output.regional_contract.dr.instance_type == "t3.small"
    error_message = "region reorder changed mapping."
  }
}

run "bad_schema_is_rejected" {
  command = plan
  variables { catalog_path = "fixtures/regions-bad-schema.json" }
  expect_failures = [check.schema_contract, output.catalog_guard]
}

run "duplicate_keys_are_rejected" {
  command = plan
  variables { catalog_path = "fixtures/regions-duplicate.json" }
  expect_failures = [check.semantic_contract, output.catalog_guard]
}

run "missing_region_is_rejected" {
  command = plan
  variables { catalog_path = "fixtures/regions-missing.json" }
  expect_failures = [check.semantic_contract, output.catalog_guard]
}

run "invalid_semantics_are_rejected" {
  command = plan
  variables { catalog_path = "fixtures/regions-invalid.json" }
  expect_failures = [check.semantic_contract, output.catalog_guard]
}

run "unsafe_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "http://example.com:4566" }
  expect_failures = [var.localstack_endpoint]
}
