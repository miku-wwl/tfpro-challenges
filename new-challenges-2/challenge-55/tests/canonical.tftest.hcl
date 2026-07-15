variables {
  catalog_path = "fixtures/catalog-v1.json"
}

run "v1_contract" {
  command = plan
  assert {
    condition = (
      output.fleet_contract.release_version == "2026.07.1" &&
      toset(output.fleet_contract.service_keys) == toset(["api", "worker"]) &&
      toset(output.fleet_contract.node_keys) == toset(["api-a", "worker-a"]) &&
      length(output.fleet_contract.addresses) == 4
    )
    error_message = "v1 fleet contract is wrong."
  }
}

run "reordered_catalog_is_stable" {
  command = plan
  variables { catalog_path = "fixtures/catalog-v1-reordered.json" }
  assert {
    condition     = toset(output.fleet_contract.service_keys) == toset(["api", "worker"]) && toset(output.fleet_contract.node_keys) == toset(["api-a", "worker-a"])
    error_message = "reordering changed business keys."
  }
}

run "v2_contract" {
  command = plan
  variables { catalog_path = "fixtures/catalog-v2.json" }
  assert {
    condition     = output.fleet_contract.release_version == "2026.07.2"
    error_message = "v2 release missing."
  }
}

run "scale_out_contract" {
  command = plan
  variables { catalog_path = "fixtures/catalog-v2-scale-out.json" }
  assert {
    condition     = toset(output.fleet_contract.node_keys) == toset(["api-a", "api-b", "worker-a"])
    error_message = "scale-out key missing."
  }
}

run "bad_schema_is_rejected" {
  command = plan
  variables { catalog_path = "fixtures/catalog-bad-schema.json" }
  expect_failures = [check.top_level_contract, check.collection_contract, output.catalog_guard]
}
run "duplicate_node_is_rejected" {
  command = plan
  variables { catalog_path = "fixtures/catalog-duplicate-node.json" }
  expect_failures = [check.identity_contract, output.catalog_guard]
}
run "missing_service_is_rejected" {
  command = plan
  variables { catalog_path = "fixtures/catalog-missing-service.json" }
  expect_failures = [check.field_contract, output.catalog_guard]
}
run "invalid_fields_are_rejected" {
  command = plan
  variables { catalog_path = "fixtures/catalog-invalid-fields.json" }
  expect_failures = [check.top_level_contract, check.field_contract, output.catalog_guard]
}
