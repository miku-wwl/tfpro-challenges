variables {
  run_id              = "c45test"
  release_version     = "v1"
  payloads            = { api = "api payload v1", worker = "worker payload v1" }
  localstack_endpoint = "http://localhost:4566"
}

run "v1_release_contract" {
  command = plan
  assert {
    condition     = output.release_contract.schema_version == 1 && output.release_contract.release_version == "v1"
    error_message = "Producer contract version metadata differs."
  }
  assert {
    condition     = toset(keys(output.release_contract.objects)) == toset(["api", "worker"])
    error_message = "Producer object keys are not semantic."
  }
}

run "map_reorder_is_stable" {
  command = plan
  variables { payloads = { worker = "worker payload v1", api = "api payload v1" } }
  assert {
    condition     = output.release_contract.catalog_sha256 == run.v1_release_contract.release_contract.catalog_sha256
    error_message = "Map order changed the catalog fingerprint."
  }
}

run "v2_preserves_object_identity" {
  command = plan
  variables {
    release_version = "v2"
    payloads        = { worker = "worker payload v2", api = "api payload v2" }
  }
  assert {
    condition     = toset(keys(output.release_contract.objects)) == toset(keys(run.v1_release_contract.release_contract.objects))
    error_message = "Release upgrade changed logical object identity."
  }
}

run "empty_release_is_rejected" {
  command = plan
  variables { payloads = {} }
  expect_failures = [check.release_nonempty]
}
run "unsafe_name_is_rejected" {
  command = plan
  variables { payloads = { "Bad Name" = "payload" } }
  expect_failures = [check.release_names]
}
run "normalized_duplicate_is_rejected" {
  command = plan
  variables { payloads = { api = "one", API = "two" } }
  expect_failures = [check.release_names]
}
run "blank_payload_is_rejected" {
  command = plan
  variables { payloads = { api = "   " } }
  expect_failures = [check.release_payloads]
}
