run "stable_filtered_catalog" {
  command = plan

  assert {
    condition     = join(",", output.service_keys) == "api,metrics,worker"
    error_message = "Only enabled prod services may be selected with stable names."
  }

  assert {
    condition = (
      output.regional_contracts.primary.api.bucket == "tfpro-c29-api-primary" &&
      output.regional_contracts.dr.api.bucket == "tfpro-c29-api-dr"
    )
    error_message = "Primary and DR bucket identities are crossed."
  }

  assert {
    condition     = output.regional_contracts.dr.api.peer_bucket == output.regional_contracts.primary.api.bucket
    error_message = "DR must consume the matching primary bucket contract."
  }

  assert {
    condition = (
      output.regional_contracts.primary.api.region == "us-east-1" &&
      output.regional_contracts.dr.api.region == "us-west-2"
    )
    error_message = "Provider-region contracts are incomplete."
  }
}

run "reordered_catalog_is_stable" {
  command = plan

  variables {
    catalog_file = "../fixtures/services-reordered.csv"
  }

  assert {
    condition     = join(",", output.service_keys) == "api,metrics,worker"
    error_message = "CSV row order must not change service identity."
  }

  assert {
    condition     = output.regional_contracts.dr.metrics.peer_bucket == output.regional_contracts.primary.metrics.bucket
    error_message = "The keyed DR-to-primary contract must survive reordering."
  }
}

run "owner_groups_are_deterministic" {
  command = plan

  assert {
    condition = (
      join(",", output.services_by_owner.platform) == "api" &&
      join(",", output.services_by_owner.data) == "worker" &&
      join(",", output.services_by_owner.observability) == "metrics"
    )
    error_message = "Owner grouping is incomplete or unstable."
  }
}

run "dev_catalog_selects_only_admin" {
  command = plan

  variables {
    target_environment = "dev"
  }

  assert {
    condition     = join(",", output.service_keys) == "admin"
    error_message = "Environment filtering must occur before graph construction."
  }
}

run "reject_unknown_environment" {
  command = plan

  variables {
    target_environment = "qa"
  }

  expect_failures = [var.target_environment]
}

run "reject_same_region" {
  command = plan

  variables {
    dr_region = "us-east-1"
  }

  expect_failures = [check.distinct_regions]
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
