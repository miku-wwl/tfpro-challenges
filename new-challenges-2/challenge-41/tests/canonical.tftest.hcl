variables {
  run_id              = "tfpro-c41-test"
  localstack_endpoint = "http://localhost:4566"
}

run "stable_module_graph" {
  command = plan
  assert {
    condition     = output.service_keys == tolist(["api", "worker"])
    error_message = "Enabled services must use stable semantic keys."
  }
  assert {
    condition     = length(output.address_contract) == 6
    error_message = "The module graph must expose exactly six managed addresses."
  }
}

run "reordered_catalog_is_stable" {
  command = plan
  variables { catalog_path = "../fixtures/services-reordered.json" }
  assert {
    condition     = output.service_keys == run.stable_module_graph.service_keys && output.address_contract == run.stable_module_graph.address_contract
    error_message = "JSON row order changed semantic identity."
  }
}

run "bad_schema_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/services-bad-schema.json" }
  expect_failures = [check.catalog_schema]
}

run "empty_catalog_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/services-empty.json" }
  expect_failures = [check.catalog_nonempty, check.catalog_enabled]
}

run "duplicate_names_are_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/services-duplicate.json" }
  expect_failures = [check.catalog_unique_names]
}

run "invalid_fields_are_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/services-invalid.json" }
  expect_failures = [check.catalog_fields, check.catalog_enabled]
}

run "no_enabled_service_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/services-disabled.json" }
  expect_failures = [check.catalog_enabled]
}
