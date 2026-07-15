variables {
  run_id            = "unit-c28"
  platform_revision = 1
}

run "canonical_platform_contract" {
  command = plan

  assert {
    condition = (
      output.platform_contract.contract_version == 1 &&
      output.platform_contract.platform_revision == 1 &&
      output.platform_contract.run_id == "unit-c28"
    )
    error_message = "The platform contract identity is incomplete."
  }
}

run "regional_bucket_contracts_are_deterministic" {
  command = plan

  assert {
    condition = (
      output.platform_contract.primary.bucket == "tfpro-c28-unit-c28-primary" &&
      output.platform_contract.dr.bucket == "tfpro-c28-unit-c28-dr" &&
      output.platform_contract.primary.manifest_key == "platform/manifest.json" &&
      output.platform_contract.dr.manifest_key == "platform/manifest.json"
    )
    error_message = "Regional bucket contracts must be deterministic."
  }
}

run "revision_is_explicit" {
  command = plan

  variables {
    platform_revision = 2
  }

  assert {
    condition     = output.platform_contract.platform_revision == 2
    error_message = "Platform revision must be published explicitly."
  }
}

run "reject_non_positive_revision" {
  command = plan

  variables {
    platform_revision = 0
  }

  expect_failures = [var.platform_revision]
}

run "reject_same_regions" {
  command = plan

  variables {
    dr_region = "us-east-1"
  }

  expect_failures = [output.platform_contract]
}

run "reject_bad_run_id" {
  command = plan

  variables {
    run_id = "BAD"
  }

  expect_failures = [var.run_id]
}

run "reject_public_endpoint" {
  command = plan

  variables {
    localstack_endpoint = "https://s3.amazonaws.com:443"
  }

  expect_failures = [var.localstack_endpoint]
}

run "reject_invalid_primary_region" {
  command = plan

  variables {
    primary_region = "invalid"
  }

  expect_failures = [var.primary_region]
}
