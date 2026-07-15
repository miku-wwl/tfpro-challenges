run "remote_state_drives_exact_iam_grants" {
  command = plan
  assert {
    condition = (
      output.access_contract.contract_version == 1 &&
      output.access_contract.consumed_revision == "v1" &&
      toset(keys(output.access_contract.grants)) == toset(["read-api", "read-worker"]) &&
      output.access_contract.grants["read-api"].artifact == "api" &&
      endswith(output.access_contract.grants["read-worker"].arn, "/releases/worker.txt")
    )
    error_message = "The IAM consumer did not derive the exact remote artifact contract."
  }
}

run "grant_reorder_is_stable" {
  command = plan
  variables { manifest_path = "../../fixtures/grants-reordered.json" }
  assert {
    condition     = toset(keys(output.access_contract.grants)) == toset(["read-api", "read-worker"])
    error_message = "Grant reorder changed stable IAM identities."
  }
}

run "stale_revision_is_rejected" {
  command = plan
  variables { expected_revision = "v2" }
  expect_failures = [aws_iam_role.consumer]
}

run "duplicate_grant_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/grants-duplicate.json" }
  expect_failures = [aws_iam_role.consumer]
}

run "unknown_artifact_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/grants-unknown.json" }
  expect_failures = [aws_iam_role.consumer]
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
