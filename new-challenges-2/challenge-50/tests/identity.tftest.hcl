run "identity_contract_is_complete" {
  command = plan
  assert {
    condition = (
      output.identity_contract.contract_version == 1 &&
      output.identity_contract.producer_run_id == var.run_id &&
      output.identity_contract.role_name == "tfpro-c50-${var.run_id}" &&
      output.identity_contract.instance_profile_name == "tfpro-c50-${var.run_id}" &&
      can(regex("^[0-9a-f]{64}$", output.identity_contract.policy_sha256))
    )
    error_message = "The identity remote-state contract is incomplete."
  }
}

run "unsupported_contract_version_is_rejected" {
  command = plan
  variables { contract_version = 2 }
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
