variables {
  foundation_state_path = "fixtures/states/foundation-valid.tfstate"
  regional_state_path   = "fixtures/states/regional-valid.tfstate"
  expected_run_id       = "fixture01"
  minimum_generation    = 7
  active_region         = "primary"
}

run "primary_promotion_contract" {
  command = plan
  assert {
    condition     = output.active_contract.active_region == "primary" && output.active_contract.address == "aws_instance.active_primary[0]" && output.active_contract.generation == 7
    error_message = "primary promotion contract invalid."
  }
}

run "dr_promotion_contract" {
  command = plan
  variables { active_region = "dr" }
  assert {
    condition     = output.active_contract.active_region == "dr" && output.active_contract.address == "aws_instance.active_dr[0]"
    error_message = "DR promotion contract invalid."
  }
}

run "foreign_regional_state_is_rejected" {
  command = plan
  variables { regional_state_path = "fixtures/states/regional-foreign.tfstate" }
  expect_failures = [check.lineage_contract, output.consumer_guard]
}

run "stale_linked_states_are_rejected" {
  command = plan
  variables {
    foundation_state_path = "fixtures/states/foundation-stale.tfstate"
    regional_state_path   = "fixtures/states/regional-stale.tfstate"
  }
  expect_failures = [check.freshness_contract, output.consumer_guard]
}

run "unsafe_promotion_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "http://example.com:4566" }
  expect_failures = [var.localstack_endpoint]
}
