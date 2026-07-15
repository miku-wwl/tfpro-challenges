mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "000000000000" }
  }
}

run "canonical_release_contract" {
  command = plan
  variables {
    name_prefix = "tfpro-c36-mock"
  }
  assert {
    condition     = output.active_artifact_ids == tolist(["api-config", "release-notes", "worker-bootstrap"])
    error_message = "只允许三个 enabled artifacts 进入 graph。"
  }
  assert {
    condition     = output.resource_addresses.objects == tolist(["aws_s3_object.artifact[\"api-config\"]", "aws_s3_object.artifact[\"release-notes\"]", "aws_s3_object.artifact[\"worker-bootstrap\"]"])
    error_message = "对象地址必须使用 artifact_id。"
  }
  assert {
    condition     = output.release_contract.artifacts.api-config.content_type == "application/json"
    error_message = "content_type 必须来自规范化 manifest。"
  }
}

run "reordered_manifest_is_stable" {
  command = plan
  variables {
    name_prefix   = "tfpro-c36-mock"
    manifest_path = "../fixtures/manifest-reordered.json"
  }
  assert {
    condition     = output.active_artifact_ids == tolist(["api-config", "release-notes", "worker-bootstrap"])
    error_message = "manifest 重排不得改变制品身份。"
  }
}

run "duplicate_artifact_id_is_rejected" {
  command = plan
  variables { manifest_path = "../fixtures/manifest-duplicate-id.json" }
  expect_failures = [check.artifact_ids_unique]
}

run "duplicate_object_key_is_rejected" {
  command = plan
  variables { manifest_path = "../fixtures/manifest-duplicate-key.json" }
  expect_failures = [check.object_keys_unique]
}

run "empty_artifact_id_is_rejected" {
  command = plan
  variables { manifest_path = "../fixtures/manifest-invalid-fields.json" }
  expect_failures = [check.artifact_fields_valid]
}

run "empty_content_type_is_rejected" {
  command = plan
  variables { manifest_path = "../fixtures/manifest-empty-content-type.json" }
  expect_failures = [check.artifact_fields_valid]
}

run "empty_owner_is_rejected" {
  command = plan
  variables { manifest_path = "../fixtures/manifest-empty-owner.json" }
  expect_failures = [check.artifact_fields_valid]
}

run "invalid_enabled_is_rejected" {
  command = plan
  variables { manifest_path = "../fixtures/manifest-invalid-enabled.json" }
  expect_failures = [check.artifact_fields_valid]
}

run "missing_source_is_rejected" {
  command = plan
  variables { manifest_path = "../fixtures/manifest-missing-source.json" }
  expect_failures = [check.artifact_sources_exist]
}

run "path_escape_is_rejected" {
  command = plan
  variables { manifest_path = "../fixtures/manifest-path-escape.json" }
  expect_failures = [check.artifact_sources_confined]
}

run "empty_manifest_is_rejected" {
  command = plan
  variables { manifest_path = "../fixtures/manifest-empty.json" }
  expect_failures = [check.manifest_not_empty]
}

run "non_loopback_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com" }
  expect_failures = [var.localstack_endpoint]
}
