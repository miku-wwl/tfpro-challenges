variables {
  run_id              = "tfpro-c44-test"
  localstack_endpoint = "http://localhost:4566"
}

run "v1_interface_compiles" {
  command = plan
  assert {
    condition     = output.interface_contract.bundle_keys == tolist(["api", "worker"])
    error_message = "V1 bundle keys are not stable."
  }
  assert {
    condition     = length(output.address_contract) == 10 && output.interface_contract.source_version == 1
    error_message = "V1 must compile ten managed addresses."
  }
}

run "v1_reorder_is_stable" {
  command = plan
  variables { catalog_path = "../fixtures/catalog-v1-reordered.json" }
  assert {
    condition     = output.address_contract == run.v1_interface_compiles.address_contract && output.interface_contract.normalized == run.v1_interface_compiles.interface_contract.normalized
    error_message = "V1 row/key order changed the normalized interface."
  }
}

run "v2_interface_preserves_identity" {
  command = plan
  variables { catalog_path = "../fixtures/catalog-v2.json" }
  assert {
    condition     = output.address_contract == run.v1_interface_compiles.address_contract && output.interface_contract.source_version == 2
    error_message = "V2 changed resource identity."
  }
  assert {
    condition     = output.interface_contract.normalized.api.actions == tolist(["s3:GetObject", "s3:GetObjectVersion"])
    error_message = "V2 IAM actions were not canonicalized."
  }
}

run "bad_schema_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/catalog-bad-schema.json" }
  expect_failures = [check.interface_schema, check.interface_shape]
}
run "duplicate_bundle_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/catalog-duplicate.json" }
  expect_failures = [check.interface_identity]
}
run "unsafe_key_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/catalog-invalid-key.json" }
  expect_failures = [check.artifact_contract]
}
run "wildcard_action_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/catalog-invalid-action.json" }
  expect_failures = [check.identity_contract]
}
run "digest_mismatch_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/catalog-bad-digest.json" }
  expect_failures = [check.artifact_contract]
}
run "unknown_field_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/catalog-extra-field.json" }
  expect_failures = [check.interface_shape]
}
