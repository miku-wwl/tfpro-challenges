mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = { id = "mock-artifact-bucket", bucket = "mock-artifact-bucket" }
  }
}

variables {
  run_id             = "mock-c39"
  state_bucket       = "mock-state-bucket"
  producer_state_key = "producer/terraform.tfstate"
}

run "producer_publishes_versioned_contract" {
  command = plan
  assert {
    condition = (
      output.delivery_contract.contract_version == 1 &&
      output.delivery_contract.region == "us-east-1" &&
      output.delivery_contract.producer.state_bucket == "mock-state-bucket" &&
      output.delivery_contract.producer.state_key == "producer/terraform.tfstate" &&
      output.delivery_contract.artifacts.bucket_name == "mock-c39-artifacts" &&
      output.delivery_contract.artifacts.versioning == "Enabled" &&
      output.delivery_contract.run_id == "mock-c39"
    )
    error_message = "producer delivery contract 不完整。"
  }
}

run "invalid_run_id_is_rejected" {
  command = plan
  variables { run_id = "BAD/RUN" }
  expect_failures = [var.run_id]
}

run "unsupported_contract_version_is_rejected" {
  command = plan
  variables { contract_version = 2 }
  expect_failures = [var.contract_version]
}

run "endpoint_with_path_is_rejected" {
  command = plan
  variables { localstack_endpoint = "http://localhost:4566/evil" }
  expect_failures = [var.localstack_endpoint]
}
