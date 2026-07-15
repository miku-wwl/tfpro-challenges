run "deployment_contract" {
  command = plan
  assert {
    condition     = toset(output.deployment_contract.keys) == toset(["api@primary", "api@dr", "worker@primary", "metrics@dr"])
    error_message = "expanded deployment keys mismatch"
  }
  assert {
    condition     = length(output.deployment_contract.addresses) == 4
    error_message = "every name@location key must own one object address"
  }
}
run "reordered_catalog_is_stable" {
  command = plan
  variables { catalog_file = "../../fixtures/workloads-reordered.csv" }
  assert {
    condition     = toset(output.deployment_contract.keys) == toset(["api@primary", "api@dr", "worker@primary", "metrics@dr"])
    error_message = "CSV reorder changed deployment identity"
  }
}
run "duplicate_key_is_rejected" {
  command = plan
  variables { catalog_file = "../../fixtures/workloads-duplicate.csv" }
  expect_failures = [output.catalog_guard]
}
run "invalid_location_is_rejected" {
  command = plan
  variables { catalog_file = "../../fixtures/workloads-invalid-location.csv" }
  expect_failures = [output.catalog_guard]
}
