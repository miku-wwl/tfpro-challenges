run "publish_compute_contract" {
  command = plan
  assert {
    condition     = output.compute_contract.contract_version == 1 && output.compute_contract.run_id == var.run_id
    error_message = "foundation contract version/run mismatch"
  }
  assert {
    condition     = output.compute_contract.primary.region == "us-east-1" && output.compute_contract.dr.region == "us-west-2"
    error_message = "regional contract is crossed"
  }
  assert {
    condition     = output.compute_contract.primary.subnet_id == var.primary_subnet_id && output.compute_contract.dr.subnet_id == var.dr_subnet_id
    error_message = "external subnet identity was lost"
  }
}

run "invalid_run_id_is_rejected" {
  command = plan
  variables { run_id = "BAD" }
  expect_failures = [var.run_id]
}

run "unsafe_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com" }
  expect_failures = [var.localstack_endpoint]
}
