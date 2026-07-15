variables {
  foundation_state_path = "fixtures/states/foundation-valid.tfstate"
  expected_run_id       = "fixture01"
  minimum_generation    = 7
}

run "regional_consumer_contract" {
  command = plan
  assert {
    condition     = output.run_id == "fixture01" && output.generation == 7 && output.foundation_contract_id == "cd2c852b4db8835eae3f4a8e1c91a6225125762563bf1a9da9f2f0fe9bb15609"
    error_message = "regional consumer contract invalid."
  }
}

run "foreign_foundation_state_is_rejected" {
  command = plan
  variables { foundation_state_path = "fixtures/states/foundation-foreign.tfstate" }
  expect_failures = [check.lineage_contract, output.consumer_guard]
}

run "stale_foundation_state_is_rejected" {
  command = plan
  variables { foundation_state_path = "fixtures/states/foundation-stale.tfstate" }
  expect_failures = [check.freshness_contract, output.consumer_guard]
}

run "missing_foundation_schema_is_rejected" {
  command = plan
  variables { foundation_state_path = "fixtures/states/foundation-missing.tfstate" }
  expect_failures = [check.remote_schema, output.consumer_guard]
}

run "tampered_foundation_contract_is_rejected" {
  command = plan
  variables { foundation_state_path = "fixtures/states/foundation-tampered.tfstate" }
  expect_failures = [check.lineage_contract, output.consumer_guard]
}

run "unsafe_regional_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "http://example.com:4566" }
  expect_failures = [var.localstack_endpoint]
}
