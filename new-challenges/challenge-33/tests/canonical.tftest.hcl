run "environment_catalog_contract" {
  command = plan

  variables {
    name_prefix  = "plan-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services.csv"
  }

  assert {
    condition     = output.release_contract.environment == "dev"
    error_message = "canonical tests 必须使用显式 dev environment。"
  }

  assert {
    condition     = toset(output.release_contract.services) == toset(["api", "worker"])
    error_message = "启用服务 key 不稳定。"
  }

  assert {
    condition = output.release_contract.buckets == {
      api    = "plan-c33-dev-api-unit"
      worker = "plan-c33-dev-worker-unit"
    }
    error_message = "bucket 名称必须包含显式 environment 和稳定 service key。"
  }

  assert {
    condition = output.release_contract.objects == {
      api    = "releases/dev.json"
      worker = "releases/dev.json"
    }
    error_message = "object key 必须包含显式 environment。"
  }

  assert {
    condition = output.release_contract.environment_tags == {
      buckets = { api = "dev", worker = "dev" }
      objects = { api = "dev", worker = "dev" }
    }
    error_message = "S3 bucket/object 的 Environment tags 没有来自显式输入。"
  }

  assert {
    condition = output.release_contract.owners == {
      api    = "platform"
      worker = "data"
    }
    error_message = "owner 合同错误。"
  }
}

run "reordered_catalog_keeps_identity" {
  command = plan

  variables {
    name_prefix  = "plan-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-reordered.csv"
  }

  assert {
    condition = (
      output.release_contract.buckets == {
        api    = "plan-c33-dev-api-unit"
        worker = "plan-c33-dev-worker-unit"
      } &&
      output.release_contract.objects == {
        api    = "releases/dev.json"
        worker = "releases/dev.json"
      } &&
      output.release_contract.environment_tags == {
        buckets = { api = "dev", worker = "dev" }
        objects = { api = "dev", worker = "dev" }
      }
    )
    error_message = "CSV 重排行改变了资源身份。"
  }
}

run "invalid_environment_is_rejected" {
  command = plan

  variables {
    environment  = "qa"
    name_prefix  = "plan-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services.csv"
  }

  expect_failures = [var.environment]
}

run "bad_service_is_rejected" {
  command = plan

  variables {
    name_prefix  = "plan-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-bad-service.csv"
  }

  expect_failures = [check.catalog_fields_valid, output.catalog_guard]
}

run "empty_owner_is_rejected" {
  command = plan

  variables {
    name_prefix  = "plan-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-empty-owner.csv"
  }

  expect_failures = [check.catalog_fields_valid, output.catalog_guard]
}

run "invalid_enabled_is_rejected" {
  command = plan

  variables {
    name_prefix  = "plan-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-invalid-enabled.csv"
  }

  expect_failures = [check.enabled_values_valid, output.catalog_guard]
}

run "duplicate_across_enabled_and_disabled_is_rejected" {
  command = plan

  variables {
    name_prefix  = "plan-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-duplicate.csv"
  }

  expect_failures = [check.services_unique, output.catalog_guard]
}

run "empty_catalog_is_rejected" {
  command = plan

  variables {
    name_prefix  = "plan-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-empty.csv"
  }

  expect_failures = [check.catalog_not_empty, output.catalog_guard]
}
