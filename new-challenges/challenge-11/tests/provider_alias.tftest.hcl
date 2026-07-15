run "provider_alias_contract" {
  command = plan

  assert {
    condition     = output.provider_regions == { primary = "us-east-1", recovery = "us-west-2" }
    error_message = "The two provider regions must remain distinct and deterministic."
  }

  assert {
    condition     = output.bucket_names.primary == "tfpro-c11-primary" && output.bucket_names.recovery == "tfpro-c11-recovery"
    error_message = "Bucket names must identify the provider slot."
  }
}

run "custom_prefix_is_propagated" {
  command = plan

  variables {
    name_prefix = "c11-contract"
  }

  assert {
    condition     = output.bucket_names.primary == "c11-contract-primary" && output.bucket_names.recovery == "c11-contract-recovery"
    error_message = "The child module must consume the caller prefix."
  }
}

run "same_region_is_rejected" {
  command = plan

  variables {
    recovery_region = "us-east-1"
  }

  expect_failures = [check.regions_differ]
}

run "invalid_prefix_is_rejected" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

run "non_loopback_endpoint_is_rejected" {
  command = plan

  variables {
    localstack_endpoint = "https://s3.amazonaws.com:443"
  }

  expect_failures = [var.localstack_endpoint]
}
