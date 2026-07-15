run "remote_contracts_drive_dual_region_workload" {
  command = plan
  assert {
    condition = (
      output.workload_contract.release == var.expected_release &&
      output.workload_contract.fleet_keys == tolist(["api@primary", "worker@dr"]) &&
      output.workload_contract.primary.location == "primary" &&
      output.workload_contract.primary.subnet_id == var.primary_subnet_id &&
      output.workload_contract.primary.image_id == var.primary_image_id &&
      output.workload_contract.dr.location == "dr" &&
      output.workload_contract.dr.subnet_id == var.dr_subnet_id &&
      output.workload_contract.dr.image_id == var.dr_image_id
    )
    error_message = "The workload did not consume and route both remote-state contracts."
  }
}

run "catalog_reorder_is_address_stable" {
  command = plan
  variables { catalog_path = "../../fixtures/fleets-reordered.json" }
  assert {
    condition     = output.workload_contract.fleet_keys == tolist(["api@primary", "worker@dr"])
    error_message = "Catalog order changed stable fleet identity."
  }
}

run "duplicate_fleet_is_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/fleets-duplicate.json" }
  expect_failures = [output.workload_contract]
}

run "invalid_location_is_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/fleets-invalid-location.json" }
  expect_failures = [output.workload_contract]
}

run "invalid_capacity_is_rejected" {
  command = plan
  variables { catalog_path = "../../fixtures/fleets-invalid-capacity.json" }
  expect_failures = [output.workload_contract]
}

run "stale_expected_release_is_rejected" {
  command = plan
  variables { expected_release = "2026.07.9" }
  expect_failures = [output.workload_contract]
}

run "wrong_platform_state_key_is_rejected" {
  command = plan
  variables { platform_state_key = "wrong/terraform.tfstate" }
  expect_failures = [var.platform_state_key]
}

run "public_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com:443" }
  expect_failures = [var.localstack_endpoint]
}
