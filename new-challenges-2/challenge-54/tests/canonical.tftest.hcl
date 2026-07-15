variables {
  policy_json = <<-JSON
  {"contract_version":1,"workload":"audit","bucket_suffix":"evidence","secret":"vault-token-2026-rotate","statements":[{"key":"list","scope":"bucket","actions":["s3:ListBucket"]},{"key":"read-objects","scope":"objects","actions":["s3:GetObject","s3:PutObject"]}]}
  JSON
}

run "sensitive_policy_contract" {
  command = plan
  assert {
    condition     = output.ownership_contract.workload == "audit" && join(",", output.ownership_contract.statement_keys) == "list,read-objects"
    error_message = "ownership contract invalid."
  }
}

run "statement_reorder_is_stable" {
  command = plan
  variables {
    policy_json = <<-JSON
    {"statements":[{"actions":["s3:PutObject","s3:GetObject"],"scope":"objects","key":"read-objects"},{"scope":"bucket","key":"list","actions":["s3:ListBucket"]}],"secret":"vault-token-2026-rotate","bucket_suffix":"evidence","workload":"audit","contract_version":1}
    JSON
  }
  assert {
    condition     = join(",", output.ownership_contract.statement_keys) == "list,read-objects"
    error_message = "statement reorder changed keys."
  }
}

run "bad_schema_is_rejected" {
  command = plan
  variables {
    policy_json = <<-JSON
    {"contract_version":1,"workload":"audit","bucket_suffix":"evidence","secret":"vault-token-2026-rotate","extra":true,"statements":[{"key":"list","scope":"bucket","actions":["s3:ListBucket"]}]}
    JSON
  }
  expect_failures = [check.schema_contract, output.catalog_guard]
}

run "bad_statement_schema_is_rejected" {
  command = plan
  variables {
    policy_json = <<-JSON
    {"contract_version":1,"workload":"audit","bucket_suffix":"evidence","secret":"vault-token-2026-rotate","statements":[{"key":"list","scope":"bucket","actions":["s3:ListBucket"],"extra":"must-not-be-declassified"}]}
    JSON
  }
  expect_failures = [check.schema_contract, output.catalog_guard]
}

run "bad_version_is_rejected" {
  command = plan
  variables {
    policy_json = <<-JSON
    {"contract_version":2,"workload":"audit","bucket_suffix":"evidence","secret":"vault-token-2026-rotate","statements":[{"key":"list","scope":"bucket","actions":["s3:ListBucket"]}]}
    JSON
  }
  expect_failures = [check.semantic_contract, output.catalog_guard]
}

run "duplicate_statement_is_rejected" {
  command = plan
  variables {
    policy_json = <<-JSON
    {"contract_version":1,"workload":"audit","bucket_suffix":"evidence","secret":"vault-token-2026-rotate","statements":[{"key":"list","scope":"bucket","actions":["s3:ListBucket"]},{"key":"list","scope":"objects","actions":["s3:GetObject"]}]}
    JSON
  }
  expect_failures = [check.semantic_contract, output.catalog_guard]
}

run "invalid_fields_and_secret_are_rejected" {
  command = plan
  variables {
    policy_json = <<-JSON
    {"contract_version":1,"workload":"AUDIT!","bucket_suffix":"Bad_Suffix","secret":"short","statements":[{"key":"BAD!","scope":"global","actions":["iam:*","s3:DeleteBucket"]}]}
    JSON
  }
  expect_failures = [check.semantic_contract, output.catalog_guard]
}

run "unsafe_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "http://example.com:4566" }
  expect_failures = [var.localstack_endpoint]
}
