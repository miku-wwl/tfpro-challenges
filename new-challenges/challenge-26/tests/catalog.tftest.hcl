mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "catalog_has_stable_keys" {
  command = plan

  assert {
    condition     = join(",", output.role_keys) == "payments-ledger,platform-delivery,security-detector"
    error_message = "角色必须使用排序后的 team-workload 稳定 key。"
  }
}

run "reordered_csv_keeps_identity" {
  command = plan

  variables {
    catalog_path = "../fixtures/access-catalog-reordered.csv"
  }

  assert {
    condition     = join(",", output.role_keys) == "payments-ledger,platform-delivery,security-detector"
    error_message = "CSV 重排不得改变角色 identity。"
  }
}

run "rejects_invalid_runtime_inputs" {
  command = plan

  variables {
    environment         = "qa"
    localstack_endpoint = "https://aws.amazon.com"
  }

  expect_failures = [var.environment, var.localstack_endpoint]
}

run "rejects_unsafe_catalog" {
  command = plan

  variables {
    catalog_path        = "../fixtures/access-catalog-invalid.csv"
    policy_catalog_path = "../fixtures/policy-catalog-invalid.json"
  }

  expect_failures = [
    check.unique_identities,
    check.known_least_privilege_policies,
    check.session_duration_range,
    terraform_data.catalog_contract,
  ]
}
