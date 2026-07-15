run "v1_compiles_real_dual_region_contract" {
  command = plan
  assert {
    condition = (
      output.release_contract.fleet_keys == tolist(["api@primary", "worker@dr"]) &&
      output.release_contract.replica_keys == tolist(["api@primary#01", "worker@dr#01"]) &&
      output.release_contract.primary.subnet_id == var.primary_subnet_id &&
      output.release_contract.dr.subnet_id == var.dr_subnet_id &&
      output.release_contract.primary.image_id == var.primary_image_id &&
      output.release_contract.dr.image_id == var.dr_image_id
    )
    error_message = "The v1 provider-routed release contract is incomplete."
  }
}

run "reordered_v1_is_stable" {
  command = plan
  variables { catalog_path = "../fixtures/catalog-v1-reordered.json" }
  assert {
    condition     = output.release_contract.replica_keys == tolist(["api@primary#01", "worker@dr#01"])
    error_message = "Catalog order changed replica identity."
  }
}

run "v2_rollout_and_capacity_are_explicit" {
  command = plan
  variables { catalog_path = "../fixtures/catalog-v2.json" }
  assert {
    condition = (
      output.release_contract.replica_keys == tolist(["api@primary#01", "worker@dr#01", "worker@dr#02"]) &&
      output.release_contract.primary.location == "primary" && output.release_contract.dr.location == "dr"
    )
    error_message = "The v2 rollout/capacity contract is incorrect."
  }
}

run "invalid_schema_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/invalid-schema-version.json" }
  expect_failures = [aws_iam_role.runtime]
}
run "empty_catalog_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/invalid-empty.json" }
  expect_failures = [aws_iam_role.runtime]
}
run "duplicate_fleet_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/invalid-duplicate-fleet.json" }
  expect_failures = [aws_iam_role.runtime]
}
run "invalid_location_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/invalid-location.json" }
  expect_failures = [aws_iam_role.runtime]
}
run "invalid_capacity_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/invalid-capacity-range.json" }
  expect_failures = [aws_iam_role.runtime]
}
run "public_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com:443" }
  expect_failures = [var.localstack_endpoint]
}
run "invalid_run_id_is_rejected" {
  command = plan
  variables { run_id = "BAD" }
  expect_failures = [var.run_id]
}
