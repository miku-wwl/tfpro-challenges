variables {
  run_id              = "c46-canonical"
  localstack_endpoint = "http://localhost:4566"
  catalog_path        = "../fixtures/catalog-v1.json"
}

run "v1_contract_is_complete" {
  command = plan

  assert {
    condition = (
      output.release_contract.schema_version == 1 &&
      output.release_contract.release == "v1" &&
      output.release_contract.account_id == "000000000000" &&
      output.release_contract.bucket_name == "tfpro-c46-c46-canonical" &&
      output.release_contract.object_addresses == tolist([
        "aws_s3_object.artifact[\"api\"]",
        "aws_s3_object.artifact[\"worker\"]"
      ])
    )
    error_message = "The v1 release contract is incomplete or unstable."
  }

  assert {
    condition = (
      output.release_contract.artifacts.api.key == "releases/api.txt" &&
      output.release_contract.artifacts.api.owner == "platform" &&
      output.release_contract.artifacts.api.content_sha256 == sha256("api release payload v1") &&
      output.release_contract.artifacts.worker.content_sha256 == sha256("worker release payload v1")
    )
    error_message = "The artifact key/owner/digest contract is incorrect."
  }
}

run "reordered_catalog_is_semantically_identical" {
  command = plan

  variables {
    catalog_path = "../fixtures/catalog-v1-reordered.json"
  }

  assert {
    condition = output.release_contract.semantic_fingerprint == sha256(jsonencode({
      schema_version = 1
      release        = "v1"
      artifacts = {
        api = {
          key            = "releases/api.txt"
          owner          = "platform"
          content_sha256 = sha256("api release payload v1")
        }
        worker = {
          key            = "releases/worker.txt"
          owner          = "operations"
          content_sha256 = sha256("worker release payload v1")
        }
      }
    }))
    error_message = "The semantic fingerprint depends on JSON array order."
  }
}

run "v2_retains_addresses_and_changes_digests" {
  command = plan

  variables {
    catalog_path = "../fixtures/catalog-v2.json"
  }

  assert {
    condition = (
      output.release_contract.release == "v2" &&
      output.release_contract.object_addresses == tolist([
        "aws_s3_object.artifact[\"api\"]",
        "aws_s3_object.artifact[\"worker\"]"
      ]) &&
      output.release_contract.artifacts.api.content_sha256 == sha256("api release payload v2") &&
      output.release_contract.artifacts.worker.content_sha256 == sha256("worker release payload v2")
    )
    error_message = "The v2 contract must retain identity while changing content digests."
  }
}

run "unsupported_schema_is_rejected" {
  command = plan

  variables {
    catalog_path = "../fixtures/catalog-invalid-schema.json"
  }

  expect_failures = [aws_s3_bucket.artifacts]
}

run "duplicate_name_is_rejected" {
  command = plan

  variables {
    catalog_path = "../fixtures/catalog-duplicate-name.json"
  }

  expect_failures = [aws_s3_bucket.artifacts]
}

run "unsafe_object_key_is_rejected" {
  command = plan

  variables {
    catalog_path = "../fixtures/catalog-unsafe-key.json"
  }

  expect_failures = [aws_s3_bucket.artifacts]
}

run "public_endpoint_is_rejected" {
  command = plan

  variables {
    localstack_endpoint = "https://aws.amazon.com:443"
  }

  expect_failures = [var.localstack_endpoint]
}

run "invalid_run_id_is_rejected" {
  command = plan

  variables {
    run_id = "BAD"
  }

  expect_failures = [var.run_id]
}
