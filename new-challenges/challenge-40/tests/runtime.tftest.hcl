run "stable_dual_region_release" {
  command = plan
  assert {
    condition     = toset(output.fleet_keys) == toset(["api@primary", "worker@dr"])
    error_message = "fleet name@location identity is wrong"
  }
  assert {
    condition     = output.release_version == "2026.07.1" && output.runtime_contracts["api@primary"].artifact_digest == "5b75c35286490e1c356eb9e6c2a49225231db2b169acb8bea07811b077b3a411"
    error_message = "release contract was not propagated"
  }
  assert {
    condition     = output.runtime_contracts["api@primary"].role == "primary" && output.runtime_contracts["worker@dr"].role == "dr"
    error_message = "regional module routing is wrong"
  }
  assert {
    condition     = length(output.resource_addresses) == 4 && length(output.instance_ids) == 2
    error_message = "one launch template and instance are required per fleet"
  }
}
run "reordered_catalog_is_stable" {
  command = plan
  variables { runtime_catalog_path = "../../fixtures/runtime-reordered.json" }
  assert {
    condition     = toset(output.fleet_keys) == toset(["api@primary", "worker@dr"]) && length(output.resource_addresses) == 4
    error_message = "JSON reorder changed graph identity"
  }
}
run "duplicate_fleet_is_rejected" {
  command = plan
  variables { runtime_catalog_path = "../../fixtures/runtime-duplicate.json" }
  expect_failures = [output.catalog_guard]
}
run "invalid_location_is_rejected" {
  command = plan
  variables { runtime_catalog_path = "../../fixtures/runtime-invalid-location.json" }
  expect_failures = [output.catalog_guard]
}
run "missing_artifact_is_rejected" {
  command = plan
  variables { runtime_catalog_path = "../../fixtures/runtime-missing-artifact.json" }
  expect_failures = [output.catalog_guard]
}
run "bad_catalog_schema_is_rejected" {
  command = plan
  variables { runtime_catalog_path = "../../fixtures/runtime-bad-schema.json" }
  expect_failures = [output.catalog_guard]
}
run "bad_fleet_fields_are_rejected" {
  command = plan
  variables { runtime_catalog_path = "../../fixtures/runtime-bad-fields.json" }
  expect_failures = [output.catalog_guard]
}
run "empty_catalog_is_rejected" {
  command = plan
  variables { runtime_catalog_path = "../../fixtures/runtime-empty.json" }
  expect_failures = [output.catalog_guard]
}
run "invalid_name_is_rejected" {
  command = plan
  variables { runtime_catalog_path = "../../fixtures/runtime-invalid-name.json" }
  expect_failures = [output.catalog_guard]
}
run "invalid_instance_type_is_rejected" {
  command = plan
  variables { runtime_catalog_path = "../../fixtures/runtime-invalid-instance-type.json" }
  expect_failures = [output.catalog_guard]
}
