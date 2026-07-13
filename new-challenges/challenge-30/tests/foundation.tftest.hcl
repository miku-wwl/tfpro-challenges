mock_provider "aws" {
  mock_resource "aws_vpc" {
    defaults = { id = "vpc-primary" }
  }
  mock_resource "aws_subnet" {
    defaults = { id = "subnet-primary" }
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
}

run "dual_region_network_contract" {
  command = plan

  assert {
    condition     = output.network_contract.contract_version == 1
    error_message = "The network contract version must be explicit."
  }
  assert {
    condition     = output.network_contract.primary.region == "us-east-1" && output.network_contract.dr.region == "us-west-2"
    error_message = "The network contract must expose the two provider regions."
  }
  assert {
    condition     = output.network_contract.primary.cidr == "10.30.0.0/16" && output.network_contract.dr.cidr == "10.31.0.0/16"
    error_message = "Primary and DR network contracts are crossed."
  }
}

run "reject_same_region" {
  command = plan
  variables {
    dr_region = "us-east-1"
  }
  expect_failures = [var.dr_region]
}
