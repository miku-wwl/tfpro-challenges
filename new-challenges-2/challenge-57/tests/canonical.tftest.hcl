variables {
  run_id              = "c57-testunit01"
  localstack_endpoint = "http://localhost:4566"
  catalog_path        = "../fixtures/releases-v1.json"
}

run "compile_canonical_dual_region_contract" {
  command = plan

  assert {
    condition     = toset(output.catalog_contract.release_keys) == toset(["api", "worker"])
    error_message = "Canonical release keys differ."
  }

  assert {
    condition = toset(output.address_contract) == toset([
      "module.release[\"api\"].aws_s3_bucket.primary",
      "module.release[\"api\"].aws_s3_bucket.replica",
      "module.release[\"api\"].aws_s3_object.primary",
      "module.release[\"api\"].aws_s3_object.replica",
      "module.release[\"worker\"].aws_s3_bucket.primary",
      "module.release[\"worker\"].aws_s3_bucket.replica",
      "module.release[\"worker\"].aws_s3_object.primary",
      "module.release[\"worker\"].aws_s3_object.replica",
    ])
    error_message = "Address contract differs."
  }

  assert {
    condition = (
      output.routing_contract.primary_region == "us-east-1" &&
      output.routing_contract.replica_region == "us-west-2" &&
      output.routing_contract.releases.api.primary.account_id == "000000000000" &&
      output.routing_contract.releases.api.replica.account_id == "000000000000" &&
      output.routing_contract.releases.api.primary.bucket_name == "tfpro-c57-testunit01-api-primary" &&
      output.routing_contract.releases.api.replica.bucket_name == "tfpro-c57-testunit01-api-replica"
    )
    error_message = "Provider-slot routing contract differs."
  }
}

run "reordered_catalog_preserves_identity" {
  command = plan

  variables {
    catalog_path = "../fixtures/releases-v1-reordered.json"
  }

  assert {
    condition     = toset(output.catalog_contract.release_keys) == toset(["api", "worker"])
    error_message = "Catalog order leaked into graph identity."
  }
}

run "rollout_changes_only_payload_digest" {
  command = plan

  variables {
    catalog_path = "../fixtures/releases-v2.json"
  }

  assert {
    condition = (
      output.catalog_contract.releases.api.payload_sha256 == sha256("api-release-v2") &&
      output.catalog_contract.releases.worker.payload_sha256 == sha256("worker-release-v1")
    )
    error_message = "V2 normalized digest contract differs."
  }
}

run "reject_schema_version" {
  command = plan
  variables { catalog_path = "../fixtures/releases-bad-schema.json" }
  expect_failures = [check.catalog_schema]
}

run "reject_extra_top_level_field" {
  command = plan
  variables { catalog_path = "../fixtures/releases-extra-top.json" }
  expect_failures = [check.catalog_schema]
}

run "reject_empty_directory" {
  command = plan
  variables { catalog_path = "../fixtures/releases-empty.json" }
  expect_failures = [check.catalog_directory]
}

run "reject_release_shape" {
  command = plan
  variables { catalog_path = "../fixtures/releases-bad-shape.json" }
  expect_failures = [check.catalog_shape]
}

run "reject_normalized_duplicate_name" {
  command = plan
  variables { catalog_path = "../fixtures/releases-duplicate.json" }
  expect_failures = [check.catalog_identity]
}

run "reject_invalid_release_name" {
  command = plan
  variables { catalog_path = "../fixtures/releases-invalid-name.json" }
  expect_failures = [check.catalog_identity]
}

run "reject_invalid_owner" {
  command = plan
  variables { catalog_path = "../fixtures/releases-invalid-owner.json" }
  expect_failures = [check.catalog_identity]
}

run "reject_invalid_object_key" {
  command = plan
  variables { catalog_path = "../fixtures/releases-invalid-key.json" }
  expect_failures = [check.catalog_content]
}

run "reject_blank_payload" {
  command = plan
  variables { catalog_path = "../fixtures/releases-blank-payload.json" }
  expect_failures = [check.catalog_content]
}

run "reject_provider_slots_in_same_region" {
  command = plan

  variables {
    replica_region = "us-east-1"
  }

  expect_failures = [check.region_routing]
}
