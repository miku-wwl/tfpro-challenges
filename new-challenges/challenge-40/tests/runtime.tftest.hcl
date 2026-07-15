mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = { id = "ami-primary" }
  }
  mock_data "aws_vpc" {
    defaults = { id = "vpc-primary" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-primary"] }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-primary", latest_version = 1 }
  }
  mock_resource "aws_instance" {
    defaults = { id = "i-primary" }
  }
}

mock_provider "aws" {
  alias = "dr"
  mock_data "aws_ami" {
    defaults = { id = "ami-dr" }
  }
  mock_data "aws_vpc" {
    defaults = { id = "vpc-dr" }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-dr"] }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-dr", latest_version = 1 }
  }
  mock_resource "aws_instance" {
    defaults = { id = "i-dr" }
  }
}

run "stable_dual_region_release_rollout" {
  command = plan
  override_data {
    target = data.terraform_remote_state.artifact
    values = {
      outputs = {
        release_contract = {
          contract_version = 1
          release_version  = "2026.07.1"
          bucket_name      = "tfpro-c40-release-artifacts"
          region           = "us-east-1"
          artifacts = {
            api    = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
            worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
          }
        }
      }
    }
  }

  assert {
    condition     = join(",", output.fleet_keys) == "api@primary,worker@dr"
    error_message = "Fleet identity must be stable name@location."
  }
  assert {
    condition     = join(",", sort(keys(output.replica_ids))) == "api@primary#01,worker@dr#01"
    error_message = "Replica identity must be stable name@location#NN."
  }
  assert {
    condition     = output.runtime_contracts["api@primary"].role == "primary" && output.runtime_contracts["worker@dr"].role == "dr"
    error_message = "A fleet was routed to the wrong regional module."
  }
  assert {
    condition     = output.runtime_contracts["api@primary"].artifact_digest == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" && output.runtime_contracts["worker@dr"].artifact_digest == "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    error_message = "Artifact digests were not injected into the runtime contract."
  }
  assert {
    condition     = output.ami_ids.primary == "ami-primary" && output.ami_ids.dr == "ami-dr"
    error_message = "Default and DR AMI queries were not isolated by provider."
  }
}

run "reordered_catalog_preserves_identity" {
  command = plan
  variables {
    runtime_catalog_path = "../../fixtures/runtime-reordered.json"
  }
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  assert {
    condition     = join(",", output.fleet_keys) == "api@primary,worker@dr" && join(",", sort(keys(output.replica_ids))) == "api@primary#01,worker@dr#01"
    error_message = "JSON row order changed managed identity."
  }
}

run "reject_duplicate_fleet_identity" {
  command = plan
  variables {
    runtime_catalog_path = "../../fixtures/runtime-duplicate.json"
  }
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_unknown_location" {
  command = plan
  variables {
    runtime_catalog_path = "../../fixtures/runtime-invalid-location.json"
  }
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_incompatible_release_contract" {
  command = plan
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 2, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_release_contract_wrong_region" {
  command = plan
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-west-2", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_release_contract_bad_version_format" {
  command = plan
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "latest", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_release_contract_wrong_bucket" {
  command = plan
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "wrong-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_release_contract_unsafe_artifact_key" {
  command = plan
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "../escape.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_release_contract_invalid_digest" {
  command = plan
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_incompatible_catalog_schema" {
  command = plan
  variables {
    runtime_catalog_path = "../../fixtures/runtime-bad-schema.json"
  }
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_empty_catalog" {
  command = plan
  variables {
    runtime_catalog_path = "../../fixtures/runtime-empty.json"
  }
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_invalid_fleet_name" {
  command = plan
  variables {
    runtime_catalog_path = "../../fixtures/runtime-invalid-name.json"
  }
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_invalid_instance_type" {
  command = plan
  variables {
    runtime_catalog_path = "../../fixtures/runtime-invalid-instance-type.json"
  }
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_unpublished_artifact" {
  command = plan
  variables {
    runtime_catalog_path = "../../fixtures/runtime-missing-artifact.json"
  }
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_unsafe_replica_count" {
  command = plan
  variables {
    runtime_catalog_path = "../../fixtures/runtime-invalid-capacity.json"
  }
  override_data {
    target = data.terraform_remote_state.artifact
    values = { outputs = { release_contract = { contract_version = 1, release_version = "2026.07.1", bucket_name = "tfpro-c40-release-artifacts", region = "us-east-1", artifacts = { api = { key = "releases/api/current.txt", sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }, worker = { key = "releases/worker/current.txt", sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" } } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}
