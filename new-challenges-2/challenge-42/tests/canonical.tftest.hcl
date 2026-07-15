variables {
  run_id              = "tfpro-c42-test"
  localstack_endpoint = "http://localhost:4566"
}

run "three_slots_are_explicit" {
  command = plan
  assert {
    condition     = output.route_keys == tolist(["audit", "dr", "primary"])
    error_message = "The three provider slots must be stable."
  }
  assert {
    condition     = length(output.address_contract) == 6
    error_message = "Each provider slot must own one bucket and one role."
  }
}

run "reordered_routes_are_stable" {
  command = plan
  variables { routes_path = "../fixtures/routes-reordered.json" }
  assert {
    condition     = output.route_keys == run.three_slots_are_explicit.route_keys && output.address_contract == run.three_slots_are_explicit.address_contract
    error_message = "Route row order changed the graph."
  }
}

run "bad_schema_is_rejected" {
  command = plan
  variables { routes_path = "../fixtures/routes-bad-schema.json" }
  expect_failures = [check.route_schema, check.route_slots]
}

run "duplicate_route_is_rejected" {
  command = plan
  variables { routes_path = "../fixtures/routes-duplicate.json" }
  expect_failures = [check.route_unique]
}

run "invalid_fields_are_rejected" {
  command = plan
  variables { routes_path = "../fixtures/routes-invalid.json" }
  expect_failures = [check.route_fields, check.route_slots]
}

run "missing_slot_is_rejected" {
  command = plan
  variables { routes_path = "../fixtures/routes-missing.json" }
  expect_failures = [check.route_slots]
}

run "disabled_slot_is_rejected" {
  command = plan
  variables { routes_path = "../fixtures/routes-disabled.json" }
  expect_failures = [check.route_slots]
}
