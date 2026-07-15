run "catalog_has_stable_keys" {
  command = plan

  assert {
    condition     = join(",", output.role_keys) == "payments-ledger,platform-delivery,security-detector"
    error_message = "角色必须使用排序后的 team-workload 稳定 key。"
  }
}

run "manifest_uses_the_same_stable_keys" {
  command = plan

  assert {
    condition     = join(",", sort(keys(nonsensitive(output.access_manifest)))) == "payments-ledger,platform-delivery,security-detector"
    error_message = "The sensitive manifest must preserve the logical identity keys."
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
    output.role_keys,
  ]
}

run "stage_environment_is_supported" {
  command = plan

  variables {
    environment = "stage"
  }

  assert {
    condition     = length(output.role_keys) == 3
    error_message = "A supported environment must preserve the catalog graph."
  }
}

run "rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "BAD"
  }

  expect_failures = [var.name_prefix]
}

run "rejects_unknown_region" {
  command = plan

  variables {
    aws_region = "ap-southeast-2"
  }

  expect_failures = [var.aws_region]
}
