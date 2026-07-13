mock_provider "aws" {
  mock_resource "aws_security_group" {
    defaults = { id = "sg-primary" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:000000000000:primary-events" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { name = "primary-catalog" }
  }
}

mock_provider "aws" {
  alias = "dr"
  mock_resource "aws_security_group" {
    defaults = { id = "sg-dr" }
  }
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-west-2:000000000000:dr-events" }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = { name = "dr-catalog" }
  }
}

run "platform_consumes_network_contract" {
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

  assert {
    condition     = output.platform_contract.contract_version == 1
    error_message = "The platform contract version must be explicit."
  }
  assert {
    condition     = output.platform_contract.primary.table_name == "tfpro-c30-primary-catalog" && output.platform_contract.dr.table_name == "tfpro-c30-dr-catalog"
    error_message = "Primary and DR platform resources are crossed."
  }
  assert {
    condition     = output.platform_contract.primary.region == "us-east-1" && output.platform_contract.dr.region == "us-west-2"
    error_message = "The platform contract regions are wrong."
  }
}

run "reject_same_region" {
  command = plan
  variables {
    dr_region = "us-east-1"
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
  expect_failures = [var.dr_region]
}

run "reject_incompatible_network_contract" {
  command = plan
  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        network_contract = {
          contract_version = 2
          primary          = { region = "us-east-1", vpc_id = "vpc-primary", subnet_id = "subnet-primary", cidr = "10.30.0.0/16" }
          dr               = { region = "us-west-2", vpc_id = "vpc-dr", subnet_id = "subnet-dr", cidr = "10.31.0.0/16" }
        }
      }
    }
  }
  expect_failures = [terraform_data.contract_guard]
}
