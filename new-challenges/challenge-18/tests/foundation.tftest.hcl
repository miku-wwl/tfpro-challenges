run "default_platform_contract" {
  command = plan
  assert {
    condition     = output.platform_contract.schema_version == 1 && jsonencode(sort(keys(output.platform_contract.regions))) == jsonencode(["dr", "primary"])
    error_message = "Foundation must publish schema v1 with exact regional keys."
  }
}
run "custom_prefix_propagates" {
  command = plan
  variables { name_prefix = "c18-contract" }
  assert {
    condition     = output.platform_contract.regions.primary.bucket_name == "c18-contract-primary" && output.platform_contract.regions.dr.bucket_name == "c18-contract-dr"
    error_message = "Both child modules must consume the root prefix."
  }
}
run "same_regions_are_rejected" {
  command = plan
  variables { dr_region = "us-east-1" }
  expect_failures = [check.regions_differ]
}
run "invalid_prefix_is_rejected" {
  command = plan
  variables { name_prefix = "Bad_Prefix" }
  expect_failures = [var.name_prefix]
}
