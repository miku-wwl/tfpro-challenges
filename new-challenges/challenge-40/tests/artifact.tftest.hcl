mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = { id = "mock-release-bucket" }
  }
  mock_resource "aws_s3_object" {
    defaults = { id = "mock-object" }
  }
}

run "publish_versioned_release_contract" {
  command = plan

  assert {
    condition     = output.release_contract.contract_version == 1 && output.release_contract.release_version == "2026.07.1"
    error_message = "Release contract version metadata is wrong."
  }
  assert {
    condition     = join(",", sort(keys(output.release_contract.artifacts))) == "api,worker"
    error_message = "Manifest artifacts were not published with stable names."
  }
  assert {
    condition     = output.release_contract.artifacts.api.key == "releases/api/current.txt" && output.release_contract.artifacts.api.sha256 == "5b75c35286490e1c356eb9e6c2a49225231db2b169acb8bea07811b077b3a411"
    error_message = "The API key or digest was lost from the release contract."
  }
}

run "reject_incompatible_manifest_schema" {
  command = plan
  variables {
    manifest_path = "../../fixtures/manifest-bad-schema.json"
  }
  expect_failures = [terraform_data.manifest_guard]
}

run "reject_incompatible_contract_version" {
  command = plan
  variables {
    manifest_path = "../../fixtures/manifest-bad-contract-version.json"
  }
  expect_failures = [terraform_data.manifest_guard]
}

run "reject_invalid_release_version" {
  command = plan
  variables {
    manifest_path = "../../fixtures/manifest-bad-release-version.json"
  }
  expect_failures = [terraform_data.manifest_guard]
}

run "reject_duplicate_artifact_name" {
  command = plan
  variables {
    manifest_path = "../../fixtures/manifest-duplicate.json"
  }
  expect_failures = [terraform_data.manifest_guard]
}

run "reject_digest_mismatch" {
  command = plan
  variables {
    manifest_path = "../../fixtures/manifest-bad-digest.json"
  }
  expect_failures = [terraform_data.manifest_guard]
}

run "reject_unsafe_object_key" {
  command = plan
  variables {
    manifest_path = "../../fixtures/manifest-invalid-key.json"
  }
  expect_failures = [terraform_data.manifest_guard]
}
