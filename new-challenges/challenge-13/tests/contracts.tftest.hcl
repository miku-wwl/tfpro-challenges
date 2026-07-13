run "default_catalog_is_typed_grouped_and_deterministic" {
  command = apply

  assert {
    condition     = jsonencode(output.service_keys) == jsonencode(["api", "worker"])
    error_message = "Expected sorted enabled prod service keys."
  }

  assert {
    condition     = output.service_profiles.api.port == 443 && output.service_profiles.api.capacity == 6
    error_message = "CSV numeric fields must be converted to numbers."
  }

  assert {
    condition     = jsonencode(output.services_by_owner) == jsonencode({ data = ["worker"], platform = ["api"] })
    error_message = "Services must be deterministically grouped by owner."
  }
}

run "reordered_csv_preserves_identity" {
  command = plan

  variables {
    services_file = "../fixtures/services-reordered.csv"
  }

  assert {
    condition     = jsonencode(output.service_keys) == jsonencode(["api", "worker"])
    error_message = "CSV row order must not affect semantic identity."
  }
}

run "invalid_environment_fails_variable_validation" {
  command = plan

  variables {
    target_environment = "qa"
  }

  expect_failures = [var.target_environment]
}

run "invalid_policy_fails_variable_validation" {
  command = plan

  variables {
    policy = {
      allowed_tiers      = []
      max_total_capacity = 0
    }
  }

  expect_failures = [var.policy]
}

run "invalid_port_fails_resource_precondition" {
  command = plan

  variables {
    services_file = "../fixtures/services-invalid-port.csv"
  }

  expect_failures = [terraform_data.service]
}

run "unknown_owner_fails_resource_precondition" {
  command = plan

  variables {
    services_file = "../fixtures/services-unknown-owner.csv"
  }

  expect_failures = [terraform_data.service]
}

run "invalid_tier_fails_resource_precondition" {
  command = plan

  variables {
    services_file = "../fixtures/services-invalid-tier.csv"
  }

  expect_failures = [terraform_data.service]
}

run "aggregate_capacity_fails_check" {
  command = plan

  variables {
    services_file = "../fixtures/services-over-budget.csv"
  }

  expect_failures = [check.capacity_budget]
}
