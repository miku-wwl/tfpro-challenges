run "canonical_random_fleet_graph" {
  command = plan
  assert {
    condition     = toset(output.active_fleet_ids) == toset(["api", "worker"])
    error_message = "Target fleet IDs are not deterministic."
  }
  assert {
    condition = (
      length(output.resource_addresses.placements) == 2 &&
      length(output.resource_addresses.security_groups) == 2 &&
      length(output.resource_addresses.launch_templates) == 2 &&
      length(output.resource_addresses.instances) == 2
    )
    error_message = "Each fleet must own placement, SG, LT, and instance addresses."
  }
  assert {
    condition     = output.fleet_contract.fleets.api.placement_epoch == 1 && output.fleet_contract.fleets.worker.placement_epoch == 1
    error_message = "The v1 placement generation is wrong."
  }
}

run "reordered_csv_is_stable" {
  command = plan
  variables { fleet_csv_path = "../fixtures/fleets-reordered.csv" }
  assert {
    condition     = toset(output.active_fleet_ids) == toset(["api", "worker"])
    error_message = "CSV reorder changed fleet identity."
  }
}

run "rotated_catalog_changes_only_api_epoch" {
  command = plan
  variables { fleet_csv_path = "../fixtures/fleets-rotated.csv" }
  assert {
    condition     = output.fleet_contract.fleets.api.placement_epoch == 2 && output.fleet_contract.fleets.worker.placement_epoch == 1
    error_message = "The rotated fixture has the wrong placement generations."
  }
}

run "invalid_environment_is_rejected" {
  command = plan
  variables { environment = "qa" }
  expect_failures = [var.environment]
}

run "duplicate_fleet_id_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../fixtures/fleets-duplicate.csv" }
  expect_failures = [check.fleet_ids_unique, output.catalog_guard]
}

run "unknown_subnet_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../fixtures/fleets-invalid-subnet.csv" }
  expect_failures = [check.fleet_subnets_exist, output.catalog_guard]
}

run "missing_csv_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../fixtures/does-not-exist.csv" }
  expect_failures = [var.fleet_csv_path]
}

run "non_loopback_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com" }
  expect_failures = [var.localstack_endpoint]
}

run "invalid_enabled_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../fixtures/fleets-invalid-boolean.csv" }
  expect_failures = [check.fleet_enabled_values_valid, output.catalog_guard]
}

run "empty_required_fields_are_rejected" {
  command = plan
  variables { fleet_csv_path = "../fixtures/fleets-bad-fields.csv" }
  expect_failures = [check.fleet_fields_valid, check.fleet_instance_types_valid, output.catalog_guard]
}

run "invalid_instance_type_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../fixtures/fleets-invalid-instance-type.csv" }
  expect_failures = [check.fleet_instance_types_valid, output.catalog_guard]
}

run "duplicate_candidates_are_rejected" {
  command = plan
  variables { fleet_csv_path = "../fixtures/fleets-invalid-candidates.csv" }
  expect_failures = [check.fleet_candidate_lists_valid, output.catalog_guard]
}

run "invalid_epoch_is_rejected" {
  command = plan
  variables { fleet_csv_path = "../fixtures/fleets-invalid-epoch.csv" }
  expect_failures = [check.placement_epochs_valid, output.catalog_guard]
}
