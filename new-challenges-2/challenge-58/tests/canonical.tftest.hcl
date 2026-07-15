variables {
  localstack_endpoint = "http://localhost:4566"
  catalog_path        = "../fixtures/identities-v1.json"
}

run "compile_canonical_import_contract" {
  command = plan

  assert {
    condition     = toset(output.catalog_contract.identity_keys) == toset(["api", "worker"])
    error_message = "Canonical identity keys differ."
  }

  assert {
    condition = (
      output.catalog_contract.identities.api.owner == "platform" &&
      toset(output.catalog_contract.identities.api.actions) == toset(["s3:GetObject"]) &&
      output.catalog_contract.identities.worker.owner == "delivery"
    )
    error_message = "Canonical normalized identity contract differs."
  }

  assert {
    condition = toset(output.address_contract) == toset([
      "module.identity[\"api\"].aws_iam_policy.this",
      "module.identity[\"api\"].aws_iam_role.this",
      "module.identity[\"api\"].aws_iam_role_policy_attachment.this",
      "module.identity[\"worker\"].aws_iam_policy.this",
      "module.identity[\"worker\"].aws_iam_role.this",
      "module.identity[\"worker\"].aws_iam_role_policy_attachment.this",
    ])
    error_message = "Final address contract differs."
  }
}

run "reordered_catalog_preserves_semantic_keys" {
  command = plan
  variables { catalog_path = "../fixtures/identities-v1-reordered.json" }

  assert {
    condition     = toset(output.catalog_contract.identity_keys) == toset(["api", "worker"])
    error_message = "Catalog order leaked into graph identity."
  }
}

run "v2_canonicalizes_action_order" {
  command = plan
  variables { catalog_path = "../fixtures/identities-v2.json" }

  assert {
    condition     = toset(output.catalog_contract.identities.api.actions) == toset(["s3:GetObject", "s3:GetObjectVersion"])
    error_message = "V2 actions were not canonicalized."
  }
}

run "reject_schema_version" {
  command = plan
  variables { catalog_path = "../fixtures/identities-bad-schema.json" }
  expect_failures = [check.catalog_schema]
}

run "reject_empty_directory" {
  command = plan
  variables { catalog_path = "../fixtures/identities-empty.json" }
  expect_failures = [check.catalog_directory]
}

run "reject_row_shape" {
  command = plan
  variables { catalog_path = "../fixtures/identities-bad-shape.json" }
  expect_failures = [check.catalog_shape]
}

run "reject_normalized_duplicate" {
  command = plan
  variables { catalog_path = "../fixtures/identities-duplicate.json" }
  expect_failures = [check.catalog_identity]
}

run "reject_unknown_identity_name" {
  command = plan
  variables { catalog_path = "../fixtures/identities-invalid-name.json" }
  expect_failures = [check.catalog_identity]
}

run "reject_invalid_owner" {
  command = plan
  variables { catalog_path = "../fixtures/identities-invalid-owner.json" }
  expect_failures = [check.catalog_identity]
}

run "reject_unapproved_action" {
  command = plan
  variables { catalog_path = "../fixtures/identities-invalid-action.json" }
  expect_failures = [check.catalog_actions]
}

run "reject_duplicate_action" {
  command = plan
  variables { catalog_path = "../fixtures/identities-duplicate-action.json" }
  expect_failures = [check.catalog_actions]
}
