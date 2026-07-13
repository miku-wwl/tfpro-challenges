mock_provider "aws" {}

run "workspace_catalog_contract" {
  command = plan

  variables {
    name_prefix  = "mock-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services.csv"
  }

  assert {
    condition     = output.release_contract.workspace == "dev"
    error_message = "canonical tests 必须在 dev workspace 运行。"
  }

  assert {
    condition     = toset(output.release_contract.services) == toset(["api", "worker"])
    error_message = "启用服务 key 不稳定。"
  }

  assert {
    condition = output.release_contract.buckets == {
      api    = "mock-c33-dev-api-unit"
      worker = "mock-c33-dev-worker-unit"
    }
    error_message = "bucket 名称必须包含 workspace 和稳定 service key。"
  }

  assert {
    condition = output.release_contract.topic_names == {
      api    = "mock-c33-dev-api-unit-events"
      worker = "mock-c33-dev-worker-unit-events"
    }
    error_message = "topic 名称必须包含 workspace 和稳定 service key。"
  }

  assert {
    condition = output.release_contract.workspace_tags == {
      buckets = { api = "dev", worker = "dev" }
      topics  = { api = "dev", worker = "dev" }
    }
    error_message = "S3/SNS 的 Workspace tags 没有来自当前 CLI workspace。"
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
    name_prefix  = "mock-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-reordered.csv"
  }

  assert {
    condition = (
      output.release_contract.buckets == {
        api    = "mock-c33-dev-api-unit"
        worker = "mock-c33-dev-worker-unit"
      } &&
      output.release_contract.topic_names == {
        api    = "mock-c33-dev-api-unit-events"
        worker = "mock-c33-dev-worker-unit-events"
      } &&
      output.release_contract.workspace_tags == {
        buckets = { api = "dev", worker = "dev" }
        topics  = { api = "dev", worker = "dev" }
      }
    )
    error_message = "CSV 重排行改变了资源身份。"
  }
}

run "bad_service_is_rejected" {
  command = plan

  variables {
    name_prefix  = "mock-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-bad-service.csv"
  }

  expect_failures = [terraform_data.catalog_guard]
}

run "empty_owner_is_rejected" {
  command = plan

  variables {
    name_prefix  = "mock-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-empty-owner.csv"
  }

  expect_failures = [terraform_data.catalog_guard]
}

run "invalid_enabled_is_rejected" {
  command = plan

  variables {
    name_prefix  = "mock-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-invalid-enabled.csv"
  }

  expect_failures = [terraform_data.catalog_guard]
}

run "duplicate_across_enabled_and_disabled_is_rejected" {
  command = plan

  variables {
    name_prefix  = "mock-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-duplicate.csv"
  }

  expect_failures = [terraform_data.catalog_guard]
}

run "empty_catalog_is_rejected" {
  command = plan

  variables {
    name_prefix  = "mock-c33"
    run_id       = "unit"
    catalog_file = "fixtures/services-empty.csv"
  }

  expect_failures = [terraform_data.catalog_guard]
}
