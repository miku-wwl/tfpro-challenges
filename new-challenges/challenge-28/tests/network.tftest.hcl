mock_provider "aws" {
  mock_resource "aws_vpc" { defaults = { id = "vpc-primary" } }
  mock_resource "aws_subnet" { defaults = { id = "subnet-primary" } }
}

mock_provider "aws" {
  alias = "dr"
  mock_resource "aws_vpc" { defaults = { id = "vpc-dr" } }
  mock_resource "aws_subnet" { defaults = { id = "subnet-dr" } }
}

run "dual_region_contract" {
  command = plan
  assert {
    condition     = join(",", sort(keys(output.network_contract))) == "contract_version,dr,primary"
    error_message = "network_contract must publish its version, dr, and primary."
  }
  assert {
    condition     = output.network_contract.contract_version == 1
    error_message = "network_contract version must be 1."
  }
  assert {
    condition     = output.network_contract.primary.region == "us-east-1" && output.network_contract.dr.region == "us-west-2"
    error_message = "network provider regions are wrong."
  }
}
