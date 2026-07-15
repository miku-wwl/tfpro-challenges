run "default_catalog_is_stable" {
  command = plan

  assert {
    condition     = jsonencode(sort(keys(aws_s3_object.service))) == jsonencode(["catalog", "payments"])
    error_message = "Only enabled prod services must enter the graph."
  }

  assert {
    condition     = output.release_contract.schema_version == 1 && output.release_contract.environment == "prod"
    error_message = "The producer must publish schema v1 for the selected environment."
  }
}

run "reordered_catalog_preserves_identity" {
  command = plan

  variables {
    services_file = "../../fixtures/services-reordered.csv"
  }

  assert {
    condition     = jsonencode(sort(keys(aws_s3_object.service))) == jsonencode(["catalog", "payments"])
    error_message = "Service names, not row indexes, must define identity."
  }
}

run "dev_selects_only_dev" {
  command = plan

  variables {
    environment = "dev"
  }

  assert {
    condition     = jsonencode(sort(keys(aws_s3_object.service))) == jsonencode(["preview"])
    error_message = "Environment filtering is incorrect."
  }
}

run "invalid_environment_is_rejected" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "empty_selection_is_rejected" {
  command = plan

  variables {
    services_file = "../../fixtures/services-no-enabled.csv"
  }

  expect_failures = [check.enabled_services_exist]
}
