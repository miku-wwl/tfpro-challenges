run "v2_manifest_has_stable_contract" {
  command = apply

  assert {
    condition     = output.release_manifest.schema_version == 2
    error_message = "The root must consume the v2 module manifest."
  }

  assert {
    condition     = output.release_manifest.service_name == "checkout-api"
    error_message = "The service name must pass through the v2 contract."
  }

  assert {
    condition     = jsonencode(sort(keys(output.release_manifest.artifacts))) == jsonencode(["canary", "stable"])
    error_message = "The manifest needs one artifact for each release channel."
  }
}

run "invalid_module_input_is_rejected" {
  command = plan

  variables {
    service_name = "INVALID NAME"
  }

  expect_failures = [var.service_name]
}
