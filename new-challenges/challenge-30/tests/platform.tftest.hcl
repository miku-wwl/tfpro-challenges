run "platform_contract" {
  command = plan
  assert {
    condition     = output.platform_contract.contract_version == 1 && output.platform_contract.regions.primary == "us-east-1" && output.platform_contract.regions.dr == "us-west-2"
    error_message = "platform contract mismatch"
  }
}
run "same_regions_are_rejected" {
  command = plan
  variables { dr_region = "us-east-1" }
  expect_failures = [output.foundation_guard]
}
