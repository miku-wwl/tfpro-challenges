variables {
  run_id              = "unit-c22"
  release_version     = "v1"
  localstack_endpoint = "http://127.0.0.1:4566"
  payloads = {
    api    = "api payload"
    worker = "worker payload"
  }
}
run "canonical_release_contract" {
  command = plan

  assert {
    condition = (
      output.release_contract.contract_version == 1 &&
      output.release_contract.producer_run_id == "unit-c22" &&
      output.release_contract.release_version == "v1" &&
      output.release_contract.artifact_bucket == "tfpro-c22-artifacts-unit-c22"
    )
    error_message = "The canonical release contract identity is incomplete."
  }
}

run "object_keys_and_digests_are_canonical" {
  command = plan

  assert {
    condition = (
      output.release_contract.objects.api.key == "releases/api.txt" &&
      output.release_contract.objects.worker.key == "releases/worker.txt" &&
      output.release_contract.objects.api.sha256 == sha256("api payload") &&
      output.release_contract.objects.worker.sha256 == sha256("worker payload")
    )
    error_message = "Object keys and digests must be derived from the logical catalog."
  }
}

run "map_reorder_preserves_identity" {
  command = plan

  variables {
    payloads = {
      worker = "worker payload"
      api    = "api payload"
    }
  }

  assert {
    condition     = join(",", sort(keys(output.release_contract.objects))) == "api,worker"
    error_message = "Input order must not affect logical object identity."
  }
}

run "release_version_is_explicit" {
  command = plan

  variables {
    release_version = "v2"
  }

  assert {
    condition     = output.release_contract.release_version == "v2"
    error_message = "The release version must be published explicitly."
  }
}

run "empty_catalog_is_rejected" {
  command = plan

  variables {
    payloads = {}
  }

  expect_failures = [terraform_data.catalog_guard]
}

run "unsafe_logical_name_is_rejected" {
  command = plan

  variables {
    payloads = {
      "../escape" = "payload"
    }
  }

  expect_failures = [terraform_data.catalog_guard]
}

run "blank_payload_is_rejected" {
  command = plan

  variables {
    payloads = {
      api = "   "
    }
  }

  expect_failures = [terraform_data.catalog_guard]
}

run "public_endpoint_is_rejected" {
  command = plan

  variables {
    localstack_endpoint = "https://s3.amazonaws.com:443"
  }

  expect_failures = [var.localstack_endpoint]
}

run "invalid_release_is_rejected" {
  command = plan

  variables {
    release_version = "latest"
  }

  expect_failures = [var.release_version]
}
