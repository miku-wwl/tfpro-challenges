mock_provider "aws" {
  mock_resource "aws_vpc" {
    defaults = { id = "vpc-primary" }
  }
  mock_resource "aws_subnet" {
    defaults = { id = "subnet-primary" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-primary" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::000000000000:role/mock-compute" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::000000000000:instance-profile/mock-compute" }
  }
}

mock_provider "aws" {
  alias = "dr"
  mock_resource "aws_vpc" {
    defaults = { id = "vpc-dr" }
  }
  mock_resource "aws_subnet" {
    defaults = { id = "subnet-dr" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-dr" }
  }
}

run "publish_versioned_compute_contract" {
  command = plan

  assert {
    condition     = output.compute_contract.contract_version == 1
    error_message = "The compute contract version must be explicit."
  }
  assert {
    condition     = output.compute_contract.primary.region == "us-east-1" && output.compute_contract.dr.region == "us-west-2"
    error_message = "The regional contract is crossed."
  }
  assert {
    condition     = output.compute_contract.primary.cidr == "10.35.0.0/16" && output.compute_contract.dr.cidr == "10.36.0.0/16"
    error_message = "Primary and DR network contracts must remain isolated."
  }
  assert {
    condition     = output.compute_contract.identity.instance_profile_name == "tfpro-c35-compute-profile"
    error_message = "The instance profile is absent from the contract."
  }
}

run "reject_same_region" {
  command = plan
  variables {
    dr_region = "us-east-1"
  }
  expect_failures = [terraform_data.contract_guard]
}

run "reject_same_vpc_cidr" {
  command = plan
  variables {
    dr_vpc_cidr = "10.35.0.0/16"
  }
  expect_failures = [terraform_data.contract_guard]
}
