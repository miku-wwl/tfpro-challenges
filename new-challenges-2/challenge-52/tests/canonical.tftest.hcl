variables {
  catalog_path = "fixtures/rules.csv"
}

run "stable_rule_contract" {
  command = plan

  assert {
    condition     = join(",", output.rule_contract.keys) == "admin,api,metrics" && length(output.rule_contract.addresses) == 4
    error_message = "stable rule contract is invalid."
  }
}

run "row_reorder_is_stable" {
  command = plan

  variables {
    catalog_path = "fixtures/rules-reordered.csv"
  }

  assert {
    condition     = join(",", output.rule_contract.keys) == "admin,api,metrics"
    error_message = "row reorder changed stable keys."
  }
}

run "bad_header_is_rejected" {
  command = plan

  variables {
    catalog_path = "fixtures/rules-bad-header.csv"
  }

  expect_failures = [check.schema_contract, output.catalog_guard]
}

run "duplicate_key_is_rejected" {
  command = plan

  variables {
    catalog_path = "fixtures/rules-duplicate.csv"
  }

  expect_failures = [check.semantic_contract, output.catalog_guard]
}

run "invalid_fields_are_rejected" {
  command = plan

  variables {
    catalog_path = "fixtures/rules-invalid.csv"
  }

  expect_failures = [check.semantic_contract, output.catalog_guard]
}

run "empty_catalog_is_rejected" {
  command = plan

  variables {
    catalog_path = "fixtures/rules-empty.csv"
  }

  expect_failures = [check.semantic_contract, output.catalog_guard]
}

run "unsafe_endpoint_is_rejected" {
  command = plan

  variables {
    localstack_endpoint = "http://example.com:4566"
  }

  expect_failures = [var.localstack_endpoint]
}
