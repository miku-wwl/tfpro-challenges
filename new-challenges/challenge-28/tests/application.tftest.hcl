mock_provider "aws" {
  mock_resource "aws_s3_bucket" { defaults = { id = "primary-bucket" } }
  mock_resource "aws_sns_topic" { defaults = { arn = "arn:aws:sns:us-east-1:000000000000:primary" } }
}

mock_provider "aws" {
  alias = "dr"
  mock_resource "aws_s3_bucket" { defaults = { id = "dr-bucket" } }
  mock_resource "aws_sns_topic" { defaults = { arn = "arn:aws:sns:us-west-2:000000000000:dr" } }
}

run "stable_expanded_catalog" {
  command = plan
  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        network_contract = {
          contract_version = 1
          primary          = { vpc_id = "vpc-primary", subnet_id = "subnet-primary", region = "us-east-1" }
          dr               = { vpc_id = "vpc-dr", subnet_id = "subnet-dr", region = "us-west-2" }
        }
      }
    }
  }
  assert {
    condition     = join(",", output.deployment_keys) == "api@primary,metrics@dr,metrics@primary,worker@dr"
    error_message = "catalog filtering/expansion or stable keys are wrong."
  }
  assert {
    condition     = join(",", output.deployments_by_owner.observability) == "metrics@dr,metrics@primary"
    error_message = "owner grouping must be sorted."
  }
}

run "reordered_catalog_is_stable" {
  command = plan
  variables { catalog_file = "../../fixtures/applications-reordered.csv" }
  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        network_contract = {
          contract_version = 1
          primary          = { vpc_id = "vpc-primary", subnet_id = "subnet-primary", region = "us-east-1" }
          dr               = { vpc_id = "vpc-dr", subnet_id = "subnet-dr", region = "us-west-2" }
        }
      }
    }
  }
  assert {
    condition     = join(",", output.deployment_keys) == "api@primary,metrics@dr,metrics@primary,worker@dr"
    error_message = "CSV row order changed deployment identity."
  }
}

run "reject_unknown_environment" {
  command = plan
  variables { target_environment = "qa" }
  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        network_contract = {
          contract_version = 1
          primary          = { vpc_id = "vpc-primary", subnet_id = "subnet-primary", region = "us-east-1" }
          dr               = { vpc_id = "vpc-dr", subnet_id = "subnet-dr", region = "us-west-2" }
        }
      }
    }
  }
  expect_failures = [var.target_environment]
}

run "reject_unknown_location" {
  command = plan
  variables { catalog_file = "../../fixtures/applications-invalid-location.csv" }
  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        network_contract = {
          contract_version = 1
          primary          = { vpc_id = "vpc-primary", subnet_id = "subnet-primary", region = "us-east-1" }
          dr               = { vpc_id = "vpc-dr", subnet_id = "subnet-dr", region = "us-west-2" }
        }
      }
    }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_incompatible_network_contract" {
  command = plan
  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        network_contract = {
          contract_version = 2
          primary          = { vpc_id = "vpc-primary", subnet_id = "subnet-primary", region = "us-east-1" }
          dr               = { vpc_id = "vpc-dr", subnet_id = "subnet-dr", region = "us-west-2" }
        }
      }
    }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_duplicate_deployment_key" {
  command = plan
  variables { catalog_file = "../../fixtures/applications-duplicate.csv" }
  override_data {
    target = data.terraform_remote_state.network
    values = {
      outputs = {
        network_contract = {
          contract_version = 1
          primary          = { vpc_id = "vpc-primary", subnet_id = "subnet-primary", region = "us-east-1" }
          dr               = { vpc_id = "vpc-dr", subnet_id = "subnet-dr", region = "us-west-2" }
        }
      }
    }
  }
  expect_failures = [terraform_data.contract_guard]
}
