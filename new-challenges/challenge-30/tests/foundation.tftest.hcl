run "identity_contract" {
  command = plan
  variables { run_id = "canonical-c30" }
  assert {
    condition     = output.identity_contract.contract_version == 1 && output.identity_contract.region == "us-east-1"
    error_message = "foundation contract version/region mismatch"
  }
}
run "unsafe_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com" }
  expect_failures = [var.localstack_endpoint]
}
