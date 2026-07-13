mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = { id = "ami-primary" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-primary" }
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
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-dr" }
  }
  mock_resource "aws_instance" {
    defaults = { id = "i-dr" }
  }
}

run "stable_dual_region_fleet_contract" {
  command = plan
  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        compute_contract = {
          contract_version = 1
          primary          = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", security_group_id = "sg-primary", cidr = "10.35.0.0/16" }
          dr               = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", security_group_id = "sg-dr", cidr = "10.36.0.0/16" }
          identity         = { role_name = "compute-role", role_arn = "arn:mock", instance_profile_name = "compute-profile" }
        }
      }
    }
  }

  assert {
    condition     = join(",", output.fleet_keys) == "api@dr,api@primary,worker@primary"
    error_message = "Filtering or stable fleet identity is wrong."
  }
  assert {
    condition     = output.fleet_contracts["api@primary"].role == "primary" && output.fleet_contracts["api@dr"].role == "dr"
    error_message = "A fleet was routed to the wrong provider role."
  }
  assert {
    condition     = output.fleet_contracts["api@primary"].subnet_id == "subnet-primary" && output.fleet_contracts["api@dr"].subnet_id == "subnet-dr"
    error_message = "A fleet consumed the wrong regional subnet."
  }
  assert {
    condition     = join(",", sort(keys(output.replica_ids))) == "api@dr#01,api@primary#01,worker@primary#01,worker@primary#02"
    error_message = "Replica keys must be stable name@location#NN identities."
  }
  assert {
    condition     = output.fleet_contracts["worker@primary"].desired_capacity == 2 && length(output.fleet_contracts["worker@primary"].instance_ids) == 2
    error_message = "Desired capacity must behaviorally expand worker into two replicas."
  }
  assert {
    condition     = join(",", output.fleets_by_owner.platform) == "api@dr,api@primary"
    error_message = "Owner grouping is incomplete or unstable."
  }
}

run "reordered_csv_is_zero_identity_change" {
  command = plan
  variables {
    fleet_csv_path = "../../fixtures/fleet-reordered.csv"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { compute_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", security_group_id = "sg-primary", cidr = "10.35.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", security_group_id = "sg-dr", cidr = "10.36.0.0/16" }, identity = { role_name = "compute-role", role_arn = "arn:mock", instance_profile_name = "compute-profile" } } } }
  }
  assert {
    condition     = join(",", output.fleet_keys) == "api@dr,api@primary,worker@primary"
    error_message = "CSV row order changed fleet identity."
  }
  assert {
    condition     = join(",", sort(keys(output.replica_ids))) == "api@dr#01,api@primary#01,worker@primary#01,worker@primary#02"
    error_message = "CSV row order changed replica identity."
  }
}

run "reject_unknown_environment" {
  command = plan
  variables {
    target_environment = "qa"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { compute_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", security_group_id = "sg-primary", cidr = "10.35.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", security_group_id = "sg-dr", cidr = "10.36.0.0/16" }, identity = { role_name = "compute-role", role_arn = "arn:mock", instance_profile_name = "compute-profile" } } } }
  }
  expect_failures = [var.target_environment]
}

run "reject_unknown_location" {
  command = plan
  variables {
    fleet_csv_path = "../../fixtures/fleet-invalid-location.csv"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { compute_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", security_group_id = "sg-primary", cidr = "10.35.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", security_group_id = "sg-dr", cidr = "10.36.0.0/16" }, identity = { role_name = "compute-role", role_arn = "arn:mock", instance_profile_name = "compute-profile" } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_invalid_fleet_name" {
  command = plan
  variables {
    fleet_csv_path = "../../fixtures/fleet-invalid-name.csv"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { compute_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", security_group_id = "sg-primary", cidr = "10.35.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", security_group_id = "sg-dr", cidr = "10.36.0.0/16" }, identity = { role_name = "compute-role", role_arn = "arn:mock", instance_profile_name = "compute-profile" } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_duplicate_fleet_key" {
  command = plan
  variables {
    fleet_csv_path = "../../fixtures/fleet-duplicate.csv"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { compute_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", security_group_id = "sg-primary", cidr = "10.35.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", security_group_id = "sg-dr", cidr = "10.36.0.0/16" }, identity = { role_name = "compute-role", role_arn = "arn:mock", instance_profile_name = "compute-profile" } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_invalid_capacity" {
  command = plan
  variables {
    fleet_csv_path = "../../fixtures/fleet-invalid-capacity.csv"
  }
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { compute_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", security_group_id = "sg-primary", cidr = "10.35.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", security_group_id = "sg-dr", cidr = "10.36.0.0/16" }, identity = { role_name = "compute-role", role_arn = "arn:mock", instance_profile_name = "compute-profile" } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_incompatible_contract_version" {
  command = plan
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { compute_contract = { contract_version = 2, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", security_group_id = "sg-primary", cidr = "10.35.0.0/16" }, dr = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", security_group_id = "sg-dr", cidr = "10.36.0.0/16" }, identity = { role_name = "compute-role", role_arn = "arn:mock", instance_profile_name = "compute-profile" } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_contract_region_mismatch" {
  command = plan
  override_data {
    target = data.terraform_remote_state.foundation
    values = { outputs = { compute_contract = { contract_version = 1, primary = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", security_group_id = "sg-primary", cidr = "10.35.0.0/16" }, dr = { region = "us-east-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", security_group_id = "sg-dr", cidr = "10.36.0.0/16" }, identity = { role_name = "compute-role", role_arn = "arn:mock", instance_profile_name = "compute-profile" } } } }
  }
  expect_failures = [terraform_data.contract_guard]
}
