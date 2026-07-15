run "stable_dual_region_contract" {
  command = plan
  assert {
    condition     = toset(output.fleet_keys) == toset(["api@primary", "api@dr", "worker@primary"])
    error_message = "stable name@location keys are wrong"
  }
  assert {
    condition     = output.fleet_contracts["api@primary"].role == "primary" && output.fleet_contracts["api@dr"].role == "dr"
    error_message = "fleet provider routing is wrong"
  }
  assert {
    condition     = length(output.resource_addresses) == 6 && length(output.instance_ids) == 3
    error_message = "one launch template and instance are required per fleet"
  }
  assert {
    condition     = toset(output.fleets_by_owner.platform) == toset(["api@primary", "api@dr"])
    error_message = "owner grouping is incomplete"
  }
}

run "reordered_catalog_is_stable" {
  command = plan
  variables { fleet_csv_path = "../../fixtures/fleet-reordered.csv" }
  assert {
    condition     = toset(output.fleet_keys) == toset(["api@primary", "api@dr", "worker@primary"]) && length(output.resource_addresses) == 6
    error_message = "CSV reorder changed graph identity"
  }
}

run "duplicate_key_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../../fixtures/fleet-duplicate.csv" }
  expect_failures = [output.catalog_guard]
}
run "invalid_location_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../../fixtures/fleet-invalid-location.csv" }
  expect_failures = [output.catalog_guard]
}
run "invalid_name_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../../fixtures/fleet-invalid-name.csv" }
  expect_failures = [output.catalog_guard]
}
run "invalid_instance_type_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../../fixtures/fleet-invalid-instance-type.csv" }
  expect_failures = [output.catalog_guard]
}
run "invalid_boolean_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../../fixtures/fleet-invalid-enabled.csv" }
  expect_failures = [output.catalog_guard]
}
run "bad_schema_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../../fixtures/fleet-bad-schema.csv" }
  expect_failures = [output.catalog_guard]
}
run "no_enabled_fleet_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../../fixtures/fleet-no-enabled.csv" }
  expect_failures = [output.catalog_guard]
}
