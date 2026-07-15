mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = { id = "ami-11111111111111111", name = "primary-image" }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
      arn        = "arn:aws:iam::111111111111:role/primary-runner"
      user_id    = "primary-runner"
    }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::111111111111:role/primary-issuer" }
  }
  mock_resource "aws_vpc" {
    defaults = { id = "vpc-primary", cidr_block = "10.38.0.0/24" }
  }
}

mock_provider "aws" {
  alias = "dr"
  mock_data "aws_ami" {
    defaults = { id = "ami-22222222222222222", name = "dr-image" }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "222222222222"
      arn        = "arn:aws:iam::222222222222:role/dr-runner"
      user_id    = "dr-runner"
    }
  }
  mock_data "aws_iam_session_context" {
    defaults = { issuer_arn = "arn:aws:iam::222222222222:role/dr-issuer" }
  }
  mock_resource "aws_vpc" {
    defaults = { id = "vpc-dr", cidr_block = "10.38.1.0/24" }
  }
}

run "provider_slots_form_exact_contract" {
  command = plan
  assert {
    condition = (
      output.diagnostic_contract.primary.ami_id == "ami-11111111111111111" &&
      output.diagnostic_contract.dr.ami_id == "ami-22222222222222222" &&
      output.vpc_contract.primary.cidr == "10.38.0.0/24" &&
      output.vpc_contract.dr.cidr == "10.38.1.0/24" &&
      join(",", output.supply_chain_contract.provider_slots) == "aws,aws.dr"
    )
    error_message = "default/dr provider slots 或供应链合同错误。"
  }
}

run "dr_override_does_not_pollute_default" {
  command = plan
  override_data {
    target = module.diagnostics.data.aws_ami.dr
    values = { id = "ami-33333333333333333", name = "replacement" }
  }
  assert {
    condition = (
      output.diagnostic_contract.primary.ami_id == "ami-11111111111111111" &&
      output.diagnostic_contract.dr.ami_id == "ami-33333333333333333"
    )
    error_message = "DR override 污染了 default provider slot。"
  }
}

run "same_region_is_rejected" {
  command = plan
  variables { dr_region = "us-east-1" }
  expect_failures = [output.diagnostic_contract]
}

run "invalid_primary_ami_is_rejected" {
  command = plan
  override_data {
    target = module.diagnostics.data.aws_ami.primary
    values = { id = "not-an-ami", name = "bad" }
  }
  expect_failures = [output.diagnostic_contract]
}

run "invalid_dr_ami_is_rejected" {
  command = plan
  override_data {
    target = module.diagnostics.data.aws_ami.dr
    values = { id = "not-an-ami", name = "bad" }
  }
  expect_failures = [output.diagnostic_contract]
}

run "invalid_primary_account_is_rejected" {
  command = plan
  override_data {
    target = module.diagnostics.data.aws_caller_identity.primary
    values = { account_id = "bad", arn = "arn:aws:iam::111111111111:role/primary", user_id = "primary" }
  }
  override_data {
    target = module.diagnostics.data.aws_iam_session_context.primary
    values = { issuer_arn = "arn:aws:iam::bad:role/primary-issuer" }
  }
  expect_failures = [output.diagnostic_contract]
}

run "invalid_dr_account_is_rejected" {
  command = plan
  override_data {
    target = module.diagnostics.data.aws_caller_identity.dr
    values = { account_id = "bad", arn = "arn:aws:iam::222222222222:role/dr", user_id = "dr" }
  }
  override_data {
    target = module.diagnostics.data.aws_iam_session_context.dr
    values = { issuer_arn = "arn:aws:iam::bad:role/dr-issuer" }
  }
  expect_failures = [output.diagnostic_contract]
}

run "empty_primary_issuer_is_rejected" {
  command = plan
  override_data {
    target = module.diagnostics.data.aws_iam_session_context.primary
    values = { issuer_arn = "" }
  }
  expect_failures = [output.diagnostic_contract]
}

run "empty_dr_issuer_is_rejected" {
  command = plan
  override_data {
    target = module.diagnostics.data.aws_iam_session_context.dr
    values = { issuer_arn = "" }
  }
  expect_failures = [output.diagnostic_contract]
}

run "primary_issuer_from_wrong_account_is_rejected" {
  command = plan
  override_data {
    target = module.diagnostics.data.aws_iam_session_context.primary
    values = { issuer_arn = "arn:aws:iam::222222222222:role/wrong" }
  }
  expect_failures = [output.diagnostic_contract]
}

run "dr_issuer_from_wrong_account_is_rejected" {
  command = plan
  override_data {
    target = module.diagnostics.data.aws_iam_session_context.dr
    values = { issuer_arn = "arn:aws:iam::111111111111:role/wrong" }
  }
  expect_failures = [output.diagnostic_contract]
}

run "non_loopback_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com:443" }
  expect_failures = [var.localstack_endpoint]
}
