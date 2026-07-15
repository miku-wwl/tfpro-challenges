mock_provider "aws" {
  mock_resource "aws_s3_object" {
    defaults = { id = "release-object", etag = "mock-etag" }
  }
}

variables {
  state_bucket       = "mock-state-bucket"
  producer_state_key = "producer/terraform.tfstate"
  release_id         = "release-v1"
}

run "consumer_accepts_exact_contract" {
  command = plan
  override_data {
    target = data.terraform_remote_state.producer
    values = { outputs = { delivery_contract = {
      contract_version = 1
      region           = "us-east-1"
      producer         = { state_bucket = "mock-state-bucket", state_key = "producer/terraform.tfstate" }
      artifacts        = { bucket_name = "mock-artifact-bucket", versioning = "Enabled" }
      run_id           = "mock-c39"
    } } }
  }
  assert {
    condition     = output.consumed_contract == jsondecode(file("../../fixtures/expected-contract.json"))
    error_message = "consumer 没有保留精确 remote contract。"
  }
  assert {
    condition     = output.release_contract.bucket == "mock-artifact-bucket" && output.release_contract.key == "releases/release-v1.json"
    error_message = "release object 路径错误。"
  }
}

run "incompatible_version_is_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.producer
    values = { outputs = { delivery_contract = {
      contract_version = 2, region = "us-east-1"
      producer         = { state_bucket = "mock-state-bucket", state_key = "producer/terraform.tfstate" }
      artifacts        = { bucket_name = "mock-artifact-bucket", versioning = "Enabled" }, run_id = "mock-c39"
    } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "wrong_region_is_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.producer
    values = { outputs = { delivery_contract = {
      contract_version = 1, region = "us-west-2"
      producer         = { state_bucket = "mock-state-bucket", state_key = "producer/terraform.tfstate" }
      artifacts        = { bucket_name = "mock-artifact-bucket", versioning = "Enabled" }, run_id = "mock-c39"
    } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "wrong_state_bucket_is_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.producer
    values = { outputs = { delivery_contract = {
      contract_version = 1, region = "us-east-1"
      producer         = { state_bucket = "other-state-bucket", state_key = "producer/terraform.tfstate" }
      artifacts        = { bucket_name = "mock-artifact-bucket", versioning = "Enabled" }, run_id = "mock-c39"
    } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "wrong_state_key_is_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.producer
    values = { outputs = { delivery_contract = {
      contract_version = 1, region = "us-east-1"
      producer         = { state_bucket = "mock-state-bucket", state_key = "other/terraform.tfstate" }
      artifacts        = { bucket_name = "mock-artifact-bucket", versioning = "Enabled" }, run_id = "mock-c39"
    } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "invalid_artifact_bucket_is_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.producer
    values = { outputs = { delivery_contract = {
      contract_version = 1, region = "us-east-1"
      producer         = { state_bucket = "mock-state-bucket", state_key = "producer/terraform.tfstate" }
      artifacts        = { bucket_name = "", versioning = "Enabled" }, run_id = "mock-c39"
    } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "suspended_artifact_versioning_is_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.producer
    values = { outputs = { delivery_contract = {
      contract_version = 1, region = "us-east-1"
      producer         = { state_bucket = "mock-state-bucket", state_key = "producer/terraform.tfstate" }
      artifacts        = { bucket_name = "mock-artifact-bucket", versioning = "Suspended" }, run_id = "mock-c39"
    } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "invalid_producer_run_id_is_rejected" {
  command = plan
  override_data {
    target = data.terraform_remote_state.producer
    values = { outputs = { delivery_contract = {
      contract_version = 1, region = "us-east-1"
      producer         = { state_bucket = "mock-state-bucket", state_key = "producer/terraform.tfstate" }
      artifacts        = { bucket_name = "mock-artifact-bucket", versioning = "Enabled" }, run_id = "BAD/RUN"
    } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "endpoint_with_userinfo_is_rejected" {
  command = plan
  variables { localstack_endpoint = "http://user@localhost:4566" }
  override_data {
    target = data.terraform_remote_state.producer
    values = { outputs = { delivery_contract = {
      contract_version = 1, region = "us-east-1"
      producer         = { state_bucket = "mock-state-bucket", state_key = "producer/terraform.tfstate" }
      artifacts        = { bucket_name = "mock-artifact-bucket", versioning = "Enabled" }, run_id = "mock-c39"
    } } }
  }
  expect_failures = [var.localstack_endpoint]
}

run "invalid_release_id_is_rejected" {
  command = plan
  variables { release_id = "BAD/RELEASE" }
  override_data {
    target = data.terraform_remote_state.producer
    values = { outputs = { delivery_contract = {
      contract_version = 1, region = "us-east-1"
      producer         = { state_bucket = "mock-state-bucket", state_key = "producer/terraform.tfstate" }
      artifacts        = { bucket_name = "mock-artifact-bucket", versioning = "Enabled" }, run_id = "mock-c39"
    } } }
  }
  expect_failures = [var.release_id]
}
