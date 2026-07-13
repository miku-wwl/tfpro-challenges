mock_provider "aws" {
  alias = "primary"

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }
}

mock_provider "aws" {
  alias = "dr"

  mock_data "aws_region" {
    defaults = {
      name = "us-west-2"
    }
  }
}

run "nested_dual_region_contract" {
  command = plan

  variables {
    name_prefix = "tfpro-c20-mock"
  }

  assert {
    condition     = output.regional_contract.primary.bucket_name == "tfpro-c20-mock-primary"
    error_message = "primary bucket identity changed"
  }

  assert {
    condition     = output.regional_contract.dr.bucket_name == "tfpro-c20-mock-dr"
    error_message = "DR bucket identity changed"
  }

  assert {
    condition     = output.regional_contract.primary.peer_bucket == output.regional_contract.dr.bucket_name
    error_message = "primary must point to the DR bucket"
  }

  assert {
    condition     = output.regional_contract.dr.peer_bucket == output.regional_contract.primary.bucket_name
    error_message = "DR must point to the primary bucket"
  }

  assert {
    condition     = output.regional_contract.primary.region == "us-east-1" && output.regional_contract.dr.region == "us-west-2"
    error_message = "regional contract must preserve both distinct regions"
  }
}

