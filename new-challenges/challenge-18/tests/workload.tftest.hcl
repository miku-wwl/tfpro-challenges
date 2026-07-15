run "prod_catalog_expands_static_branches" {
  command = plan
  variables {
    state_bucket         = "__STATE_BUCKET__"
    foundation_state_key = "__FOUNDATION_KEY__"
  }
  assert {
    condition     = jsonencode(output.deployment_keys) == jsonencode(["api@primary", "metrics@dr", "metrics@primary", "worker@dr"])
    error_message = "Prod services must expand into stable service@location keys."
  }
}
run "reordered_catalog_preserves_contract" {
  command = plan
  variables {
    state_bucket         = "__STATE_BUCKET__"
    foundation_state_key = "__FOUNDATION_KEY__"
    catalog_file         = "../../fixtures/services-reordered.csv"
  }
  assert {
    condition     = output.contract_sha256 == run.prod_catalog_expands_static_branches.contract_sha256 && jsonencode(output.deployment_addresses) == jsonencode(run.prod_catalog_expands_static_branches.deployment_addresses)
    error_message = "CSV reorder must preserve address/hash contracts."
  }
}
run "dev_catalog_selects_admin" {
  command = plan
  variables {
    state_bucket         = "__STATE_BUCKET__"
    foundation_state_key = "__FOUNDATION_KEY__"
    target_environment   = "dev"
  }
  assert {
    condition     = jsonencode(output.deployment_keys) == jsonencode(["admin@primary"])
    error_message = "Dev filtering is incorrect."
  }
}
run "invalid_environment_is_rejected" {
  command = plan
  variables {
    state_bucket         = "__STATE_BUCKET__"
    foundation_state_key = "__FOUNDATION_KEY__"
    target_environment   = "qa"
  }
  expect_failures = [var.target_environment]
}
run "invalid_service_contract_is_rejected" {
  command = plan
  variables {
    state_bucket         = "__STATE_BUCKET__"
    foundation_state_key = "__FOUNDATION_KEY__"
    catalog_file         = "../../fixtures/services-invalid.csv"
  }
  expect_failures = [check.service_contract]
}
