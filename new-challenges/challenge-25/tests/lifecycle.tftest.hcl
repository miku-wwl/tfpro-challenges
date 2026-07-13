mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      bucket = "tfpro-c25-dev-config"
    }
  }

  mock_resource "aws_s3_object" {
    defaults = {
      etag         = "mock-etag"
      content_type = "application/json"
    }
  }

  mock_resource "aws_dynamodb_table" {
    defaults = {
      billing_mode = "PAY_PER_REQUEST"
    }
  }
}

run "publishes_one_revision_identity" {
  command = plan

  assert {
    condition     = startswith(output.revision_identity, "1:") && length(output.revision_identity) == 66
    error_message = "revision identity 必须由版本和 64 位 SHA-256 组成。"
  }

  assert {
    condition     = output.object_key == "config/current.json"
    error_message = "配置必须发布到稳定 object key。"
  }
}

run "content_change_changes_identity" {
  command = plan

  variables {
    config_version = 2
    config_path    = "../fixtures/config-v2.json"
  }

  assert {
    condition     = startswith(output.revision_identity, "2:")
    error_message = "新配置版本必须产生新 revision identity。"
  }
}

run "rejects_non_positive_version" {
  command = plan

  variables {
    config_version = 0
  }

  expect_failures = [var.config_version]
}

run "rejects_contract_mismatch" {
  command = plan

  variables {
    config_path = "../fixtures/config-invalid.json"
  }

  expect_failures = [check.config_contract]
}

