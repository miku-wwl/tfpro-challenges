run "compile_stable_canonical_directory" {
  command = plan

  assert {
    condition = (
      join(",", output.directory_contract.entry_ids) == "artifact-reader,queue-publisher" &&
      output.directory_contract.entries["artifact-reader"].role_name == "tfpro-c43-artifact-reader-role" &&
      output.directory_contract.entries["queue-publisher"].policy_name == "tfpro-c43-queue-publisher-policy"
    )
    error_message = "Stable entry IDs or IAM names were not compiled correctly."
  }

  assert {
    condition = (
      output.directory_contract.entries["artifact-reader"].statements[0].sid == "ListArtifacts" &&
      output.directory_contract.entries["artifact-reader"].statements[1].sid == "ReadArtifacts" &&
      join(",", output.directory_contract.entries["queue-publisher"].trust_services) == "ecs-tasks.amazonaws.com,lambda.amazonaws.com" &&
      join(",", output.directory_contract.entries["queue-publisher"].statements[0].actions) == "sqs:GetQueueAttributes,sqs:SendMessage"
    )
    error_message = "Statement, principal, or action canonicalization is unstable."
  }

  assert {
    condition = (
      output.identity_contract.account_id == "000000000000" &&
      startswith(output.identity_contract.issuer_arn, "arn:aws:iam::000000000000:")
    )
    error_message = "IAM/STS identity contract is incorrect."
  }
}

run "reordered_json_preserves_contract" {
  command = plan
  variables { directory_path = "../fixtures/permissions-reordered.json" }

  assert {
    condition = (
      join(",", output.directory_contract.entry_ids) == "artifact-reader,queue-publisher" &&
      output.directory_contract.entries["artifact-reader"].statements[0].sid == "ListArtifacts" &&
      output.directory_contract.entries["artifact-reader"].statements[1].sid == "ReadArtifacts" &&
      join(",", output.directory_contract.entries["queue-publisher"].trust_services) == "ecs-tasks.amazonaws.com,lambda.amazonaws.com" &&
      join(",", output.directory_contract.entries["queue-publisher"].statements[0].actions) == "sqs:GetQueueAttributes,sqs:SendMessage"
    )
    error_message = "JSON row or list order changed the canonical contract."
  }
}

run "reject_schema_version" {
  command = plan
  variables { directory_path = "../fixtures/invalid-schema-version.json" }
  expect_failures = [output.directory_contract]
}

run "reject_extra_top_field" {
  command = plan
  variables { directory_path = "../fixtures/invalid-extra-top-field.json" }
  expect_failures = [output.directory_contract]
}

run "reject_empty_directory" {
  command = plan
  variables { directory_path = "../fixtures/invalid-empty-directory.json" }
  expect_failures = [output.directory_contract]
}

run "reject_missing_entry_field" {
  command = plan
  variables { directory_path = "../fixtures/invalid-missing-entry-field.json" }
  expect_failures = [output.directory_contract]
}

run "reject_extra_statement_field" {
  command = plan
  variables { directory_path = "../fixtures/invalid-extra-statement-field.json" }
  expect_failures = [output.directory_contract]
}

run "reject_duplicate_id" {
  command = plan
  variables { directory_path = "../fixtures/invalid-duplicate-id.json" }
  expect_failures = [output.directory_contract]
}

run "reject_invalid_id" {
  command = plan
  variables { directory_path = "../fixtures/invalid-id.json" }
  expect_failures = [output.directory_contract]
}

run "reject_invalid_owner" {
  command = plan
  variables { directory_path = "../fixtures/invalid-owner.json" }
  expect_failures = [output.directory_contract]
}

run "reject_invalid_trust_service" {
  command = plan
  variables { directory_path = "../fixtures/invalid-trust-service.json" }
  expect_failures = [output.directory_contract]
}

run "reject_duplicate_trust_service" {
  command = plan
  variables { directory_path = "../fixtures/invalid-duplicate-trust.json" }
  expect_failures = [output.directory_contract]
}

run "reject_empty_statements" {
  command = plan
  variables { directory_path = "../fixtures/invalid-empty-statements.json" }
  expect_failures = [output.directory_contract]
}

run "reject_duplicate_sid" {
  command = plan
  variables { directory_path = "../fixtures/invalid-duplicate-sid.json" }
  expect_failures = [output.directory_contract]
}

run "reject_invalid_effect" {
  command = plan
  variables { directory_path = "../fixtures/invalid-effect.json" }
  expect_failures = [output.directory_contract]
}

run "reject_wildcard_action" {
  command = plan
  variables { directory_path = "../fixtures/invalid-wildcard-action.json" }
  expect_failures = [output.directory_contract]
}

run "reject_invalid_action_format" {
  command = plan
  variables { directory_path = "../fixtures/invalid-action-format.json" }
  expect_failures = [output.directory_contract]
}

run "reject_duplicate_action" {
  command = plan
  variables { directory_path = "../fixtures/invalid-duplicate-action.json" }
  expect_failures = [output.directory_contract]
}

run "reject_wildcard_resource" {
  command = plan
  variables { directory_path = "../fixtures/invalid-wildcard-resource.json" }
  expect_failures = [output.directory_contract]
}

run "reject_invalid_resource_format" {
  command = plan
  variables { directory_path = "../fixtures/invalid-resource-format.json" }
  expect_failures = [output.directory_contract]
}

run "reject_duplicate_resource" {
  command = plan
  variables { directory_path = "../fixtures/invalid-duplicate-resource.json" }
  expect_failures = [output.directory_contract]
}
