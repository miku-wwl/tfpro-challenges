run "publish_release_contract" {
  command = plan
  assert {
    condition     = output.release_contract.contract_version == 1 && output.release_contract.release_version == "2026.07.1" && output.release_contract.run_id == var.run_id
    error_message = "release contract version metadata is wrong"
  }
  assert {
    condition     = toset(keys(output.release_contract.artifacts)) == toset(["api", "worker"])
    error_message = "artifact names are not stable"
  }
  assert {
    condition     = output.release_contract.artifacts.api.key == "releases/api/current.txt" && output.release_contract.artifacts.api.sha256 == "5b75c35286490e1c356eb9e6c2a49225231db2b169acb8bea07811b077b3a411"
    error_message = "API key or digest was lost"
  }
}
run "bad_manifest_schema_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-bad-schema.json" }
  expect_failures = [output.manifest_guard]
}
run "bad_contract_version_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-bad-contract-version.json" }
  expect_failures = [output.manifest_guard]
}
run "bad_release_version_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-bad-release-version.json" }
  expect_failures = [output.manifest_guard]
}
run "duplicate_artifact_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-duplicate.json" }
  expect_failures = [output.manifest_guard]
}
run "digest_mismatch_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-bad-digest.json" }
  expect_failures = [output.manifest_guard]
}
run "unsafe_key_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-invalid-key.json" }
  expect_failures = [output.manifest_guard]
}
run "bad_artifact_fields_are_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/manifest-bad-fields.json" }
  expect_failures = [output.manifest_guard]
}
