run "canonical_revision_contract" {
  command = plan

  assert {
    condition     = startswith(output.revision_identity, "1:") && length(output.revision_identity) == 66
    error_message = "Revision identity must combine the version and a SHA-256 digest."
  }

  assert {
    condition     = endswith(output.bucket_name, "-dev-config")
    error_message = "Bucket identity must be deterministic."
  }
}

run "object_keys_are_explicit" {
  command = plan

  assert {
    condition = (
      output.object_keys.current == "config/current.json" &&
      output.object_keys.pointer == "config/revision.json" &&
      length(output.object_keys.revisions) == 1 &&
      startswith(output.object_keys.revisions[0], "config/revisions/v1-")
    )
    error_message = "Current and immutable revision object keys are incomplete."
  }
}

run "content_change_changes_revision" {
  command = plan

  variables {
    config_version = 2
    config_path    = "../fixtures/config-v2.json"
  }

  assert {
    condition = (
      startswith(output.revision_identity, "2:") &&
      startswith(output.object_keys.revisions[0], "config/revisions/v2-")
    )
    error_message = "A new configuration version must publish a new immutable identity."
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

  expect_failures = [aws_s3_object.current]
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "rejects_public_endpoint" {
  command = plan

  variables {
    localstack_endpoint = "https://s3.amazonaws.com:443"
  }

  expect_failures = [var.localstack_endpoint]
}

run "rejects_unsafe_prefix" {
  command = plan

  variables {
    name_prefix = "BAD"
  }

  expect_failures = [var.name_prefix]
}
