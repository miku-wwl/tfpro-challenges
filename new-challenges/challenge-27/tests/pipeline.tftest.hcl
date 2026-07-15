run "canonical_release_graph" {
  command = plan

  variables {
    name_prefix = "tfpro-c27-test"
  }

  assert {
    condition     = output.artifact_names == tolist(["api-config", "release-notes", "worker-config"])
    error_message = "只有三个 enabled artifacts 可以进入 resource graph。"
  }

  assert {
    condition = tolist(output.managed_addresses) == tolist([
      "aws_s3_bucket.release",
      "aws_s3_object.artifact[\"api-config\"]",
      "aws_s3_object.artifact[\"release-notes\"]",
      "aws_s3_object.artifact[\"worker-config\"]"
    ])
    error_message = "managed addresses 必须以 artifact name 为稳定身份。"
  }

  assert {
    condition = tomap(output.object_keys) == tomap({
      api-config    = "releases/2026.07.1/config/api.json"
      release-notes = "releases/2026.07.1/docs/release.txt"
      worker-config = "releases/2026.07.1/config/worker.json"
    })
    error_message = "object key 必须由 release 与 manifest object_key 确定。"
  }

  assert {
    condition     = output.release_contract.application == "orders-api" && output.release_contract.environment == "dev" && output.release_contract.release == "2026.07.1"
    error_message = "release contract header 不正确。"
  }

  assert {
    condition     = length(output.release_contract.manifest_sha256) == 64 && !strcontains(jsonencode(output.release_contract), "feature")
    error_message = "release contract 必须包含规范摘要且不得泄露制品正文。"
  }
}

run "reordered_manifest_is_identical" {
  command = plan

  variables {
    name_prefix   = "tfpro-c27-test"
    manifest_path = "../fixtures/release-v1-reordered.json"
  }

  assert {
    condition     = output.artifact_names == run.canonical_release_graph.artifact_names
    error_message = "数组重排不得改变 active artifact identities。"
  }

  assert {
    condition     = output.object_keys == run.canonical_release_graph.object_keys
    error_message = "数组重排不得改变 object keys。"
  }

  assert {
    condition     = output.release_contract.manifest_sha256 == run.canonical_release_graph.release_contract.manifest_sha256
    error_message = "规范 manifest SHA-256 必须忽略数组顺序。"
  }
}

run "rejects_header_mismatch" {
  command = plan

  variables {
    manifest_path = "../fixtures/release-invalid.json"
  }

  expect_failures = [check.manifest_header]
}

run "rejects_empty_manifest" {
  command = plan

  variables {
    manifest_path = "../fixtures/release-empty.json"
  }

  expect_failures = [check.manifest_not_empty]
}

run "rejects_duplicate_artifact_name" {
  command = plan

  variables {
    manifest_path = "../fixtures/release-duplicate-name.json"
  }

  expect_failures = [check.artifact_names_unique]
}

run "rejects_duplicate_enabled_object_key" {
  command = plan

  variables {
    manifest_path = "../fixtures/release-duplicate-key.json"
  }

  expect_failures = [check.object_keys_unique]
}

run "rejects_invalid_artifact_fields" {
  command = plan

  variables {
    manifest_path = "../fixtures/release-invalid-artifact.json"
  }

  expect_failures = [check.artifact_fields_valid]
}

run "rejects_manifest_without_enabled_artifact" {
  command = plan

  variables {
    manifest_path = "../fixtures/release-no-enabled.json"
  }

  expect_failures = [check.enabled_artifacts_present]
}

run "rejects_non_loopback_endpoint" {
  command = plan

  variables {
    localstack_endpoint = "https://s3.amazonaws.com"
  }

  expect_failures = [var.localstack_endpoint]
}
