mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = { id = "primary-bucket" }
  }
  mock_resource "aws_s3_object" {
    defaults = { key = "contracts/manifest.json" }
  }
}

mock_provider "aws" {
  alias = "dr"
  mock_resource "aws_s3_bucket" {
    defaults = { id = "dr-bucket" }
  }
  mock_resource "aws_s3_object" {
    defaults = { key = "contracts/manifest.json" }
  }
}

run "stable_three_state_contract" {
  command = plan
  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        network_contract = {
          contract_version = 1
          primary          = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", cidr = "10.30.0.0/16" }
          dr               = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", cidr = "10.31.0.0/16" }
        }
      }
    }
  }
  override_data {
    target = data.terraform_remote_state.platform
    values = {
      outputs = {
        platform_contract = {
          contract_version = 1
          primary          = { region = "us-east-1", sg_id = "sg-primary", topic_arn = "arn:primary", table_name = "primary-table" }
          dr               = { region = "us-west-2", sg_id = "sg-dr", topic_arn = "arn:dr", table_name = "dr-table" }
        }
      }
    }
  }

  assert {
    condition     = join(",", output.deployment_keys) == "api@dr,api@primary,metrics@dr,worker@primary"
    error_message = "Filtering, expansion, or stable deployment keys are wrong."
  }
  assert {
    condition     = output.deployment_contracts["api@primary"].security_group == "sg-primary" && output.deployment_contracts["api@dr"].security_group == "sg-dr"
    error_message = "A deployment consumed the wrong regional platform contract."
  }
  assert {
    condition     = output.deployment_contracts["metrics@dr"].subnet_id == "subnet-dr" && output.deployment_contracts["worker@primary"].subnet_id == "subnet-primary"
    error_message = "A deployment consumed the wrong regional network contract."
  }
  assert {
    condition     = join(",", output.deployments_by_owner.platform) == "api@dr,api@primary"
    error_message = "Owner grouping must be complete and sorted."
  }
}

run "reordered_catalog_is_stable" {
  command = plan
  variables {
    catalog_file = "../../fixtures/workloads-reordered.csv"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        network_contract = {
          contract_version = 1
          primary          = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", cidr = "10.30.0.0/16" }
          dr               = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", cidr = "10.31.0.0/16" }
        }
      }
    }
  }
  override_data {
    target = data.terraform_remote_state.platform
    values = {
      outputs = {
        platform_contract = {
          contract_version = 1
          primary          = { region = "us-east-1", sg_id = "sg-primary", topic_arn = "arn:primary", table_name = "primary-table" }
          dr               = { region = "us-west-2", sg_id = "sg-dr", topic_arn = "arn:dr", table_name = "dr-table" }
        }
      }
    }
  }

  assert {
    condition     = join(",", output.deployment_keys) == "api@dr,api@primary,metrics@dr,worker@primary"
    error_message = "CSV row order changed deployment identity."
  }
}

run "reject_unknown_environment" {
  command = plan
  variables {
    target_environment = "qa"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { network_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", cidr = "10.30.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", cidr = "10.31.0.0/16" } } } }
  }
  override_data {
    target = data.terraform_remote_state.platform
    values = { outputs = { platform_contract = { contract_version = 1, primary = { region = "us-east-1", sg_id = "sg-primary", topic_arn = "arn:primary", table_name = "primary-table" }, dr = { region = "us-west-2", sg_id = "sg-dr", topic_arn = "arn:dr", table_name = "dr-table" } } } }
  }
  expect_failures = [var.target_environment]
}

run "reject_same_region" {
  command = plan
  variables {
    dr_region = "us-east-1"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { network_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", cidr = "10.30.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", cidr = "10.31.0.0/16" } } } }
  }
  override_data {
    target = data.terraform_remote_state.platform
    values = { outputs = { platform_contract = { contract_version = 1, primary = { region = "us-east-1", sg_id = "sg-primary", topic_arn = "arn:primary", table_name = "primary-table" }, dr = { region = "us-west-2", sg_id = "sg-dr", topic_arn = "arn:dr", table_name = "dr-table" } } } }
  }
  expect_failures = [var.dr_region]
}

run "reject_unknown_location" {
  command = plan
  variables {
    catalog_file = "../../fixtures/workloads-invalid-location.csv"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { network_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", cidr = "10.30.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", cidr = "10.31.0.0/16" } } } }
  }
  override_data {
    target = data.terraform_remote_state.platform
    values = { outputs = { platform_contract = { contract_version = 1, primary = { region = "us-east-1", sg_id = "sg-primary", topic_arn = "arn:primary", table_name = "primary-table" }, dr = { region = "us-west-2", sg_id = "sg-dr", topic_arn = "arn:dr", table_name = "dr-table" } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_incompatible_upstream_contract" {
  command = plan
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { network_contract = { contract_version = 2, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", cidr = "10.30.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", cidr = "10.31.0.0/16" } } } }
  }
  override_data {
    target = data.terraform_remote_state.platform
    values = { outputs = { platform_contract = { contract_version = 1, primary = { region = "us-east-1", sg_id = "sg-primary", topic_arn = "arn:primary", table_name = "primary-table" }, dr = { region = "us-west-2", sg_id = "sg-dr", topic_arn = "arn:dr", table_name = "dr-table" } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_duplicate_deployment_key" {
  command = plan
  variables {
    catalog_file = "../../fixtures/workloads-duplicate.csv"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { network_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", cidr = "10.30.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", cidr = "10.31.0.0/16" } } } }
  }
  override_data {
    target = data.terraform_remote_state.platform
    values = { outputs = { platform_contract = { contract_version = 1, primary = { region = "us-east-1", sg_id = "sg-primary", topic_arn = "arn:primary", table_name = "primary-table" }, dr = { region = "us-west-2", sg_id = "sg-dr", topic_arn = "arn:dr", table_name = "dr-table" } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}
