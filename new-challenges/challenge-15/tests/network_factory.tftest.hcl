run "prod_catalog" {
  command = plan
  variables {
    network_name = "__NETWORK_NAME__"
  }
  assert {
    condition     = jsonencode(output.service_names) == jsonencode(["admin", "api", "worker"])
    error_message = "Only enabled prod ingress services must create groups."
  }
  assert {
    condition     = length(output.rule_keys) == 3 && jsonencode(sort(keys(output.subnet_ids))) == jsonencode(["app", "data"])
    error_message = "Expected three rules and both queried subnet tiers."
  }
}

run "reordered_catalog_preserves_identity" {
  command = plan
  variables {
    network_name = "__NETWORK_NAME__"
    rules_file   = "../fixtures/rules-reordered.csv"
  }
  assert {
    condition     = jsonencode(output.rule_keys) == jsonencode(["admin|prod|tcp|00022|00022|office", "api|prod|tcp|00443|00443|office", "worker|prod|tcp|09100|09100|10.42.0.0/16"])
    error_message = "CSV row order must not alter rule identity."
  }
}

run "dev_catalog_is_filtered" {
  command = plan
  variables {
    network_name       = "__NETWORK_NAME__"
    target_environment = "dev"
  }
  assert {
    condition     = jsonencode(output.service_names) == jsonencode(["api"])
    error_message = "The dev selection must contain only its enabled ingress service."
  }
}

run "unknown_environment_is_rejected" {
  command = plan
  variables {
    network_name       = "__NETWORK_NAME__"
    target_environment = "qa"
  }
  expect_failures = [var.target_environment]
}

run "invalid_source_is_rejected" {
  command = plan
  variables {
    network_name = "__NETWORK_NAME__"
    rules_file   = "../fixtures/rules-invalid-source.csv"
  }
  expect_failures = [check.rule_contract]
}

run "invalid_prefix_is_rejected" {
  command = plan
  variables {
    network_name = "__NETWORK_NAME__"
    name_prefix  = "Bad_Prefix"
  }
  expect_failures = [var.name_prefix]
}
