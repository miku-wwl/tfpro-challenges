run "default_inventory_contract" {
  command = plan
  assert {
    condition     = jsonencode(output.service_names) == jsonencode(["api", "worker"]) && length(output.managed_addresses) == 4
    error_message = "The default enabled inventory/address contract is wrong."
  }
}

run "reordered_catalog_is_stable" {
  command = plan
  variables { catalog_file = "../fixtures/services-reordered.json" }
  assert {
    condition     = output.inventory_sha256 == run.default_inventory_contract.inventory_sha256 && jsonencode(output.managed_addresses) == jsonencode(run.default_inventory_contract.managed_addresses)
    error_message = "Array reorder must preserve canonical hash and addresses."
  }
}

run "staging_changes_context_not_identity" {
  command = plan
  variables { environment = "staging" }
  assert {
    condition     = jsonencode(output.service_names) == jsonencode(["api", "worker"])
    error_message = "Environment context must not replace semantic service keys."
  }
}

run "invalid_environment_is_rejected" {
  command = plan
  variables { environment = "qa" }
  expect_failures = [var.environment]
}

run "duplicate_names_are_rejected" {
  command = plan
  variables { catalog_file = "../fixtures/services-duplicate.json" }
  expect_failures = [check.service_names_unique]
}

run "invalid_fields_are_rejected" {
  command = plan
  variables { catalog_file = "../fixtures/services-invalid.json" }
  expect_failures = [check.service_fields_valid]
}

run "no_enabled_service_is_rejected" {
  command = plan
  variables { catalog_file = "../fixtures/services-no-enabled.json" }
  expect_failures = [check.enabled_services_present]
}
