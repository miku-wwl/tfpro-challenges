mock_provider "aws" {
  alias = "primary"

  mock_data "aws_ami" {
    defaults = {
      id   = "ami-11111111111111111"
      name = "mock-primary-image"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
      arn        = "arn:aws:iam::111111111111:role/primary-runner"
      user_id    = "primary-runner"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::111111111111:role/primary-issuer"
    }
  }
}

mock_provider "aws" {
  alias = "dr"

  mock_data "aws_ami" {
    defaults = {
      id   = "ami-22222222222222222"
      name = "mock-dr-image"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "222222222222"
      arn        = "arn:aws:iam::222222222222:role/dr-runner"
      user_id    = "dr-runner"
    }
  }

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn = "arn:aws:iam::222222222222:role/dr-issuer"
    }
  }
}

run "mock_data_exposes_provider_diagnostics" {
  command = plan

  variables {
    name_prefix = "mock-c34"
  }

  assert {
    condition     = output.diagnostic_contract == jsondecode(file("fixtures/mock-diagnostics.json"))
    error_message = "mock_data 没有形成精确的双区域诊断合同。"
  }

  assert {
    condition     = output.diagnostic_guard.validated
    error_message = "合法诊断数据没有通过统一 guard。"
  }

  assert {
    condition = (
      output.resource_contract.primary.cidr == "10.34.0.0/24" &&
      output.resource_contract.dr.cidr == "10.34.1.0/24"
    )
    error_message = "双区域 VPC 合同错误。"
  }
}

run "dr_override_is_isolated" {
  command = plan

  variables {
    name_prefix = "mock-c34"
  }

  override_data {
    target = module.diagnostics.data.aws_ami.dr
    values = {
      id   = "ami-33333333333333333"
      name = "mock-dr-replacement"
    }
  }

  assert {
    condition = (
      output.diagnostic_contract.primary.ami_id == "ami-11111111111111111" &&
      output.diagnostic_contract.dr.ami_id == "ami-33333333333333333"
    )
    error_message = "DR override 不应污染 primary data source。"
  }
}

run "same_region_is_rejected" {
  command = plan

  variables {
    name_prefix = "mock-c34"
    dr_region   = "us-east-1"
  }

  expect_failures = [output.diagnostic_guard]
}

run "invalid_ami_is_rejected" {
  command = plan

  variables {
    name_prefix = "mock-c34"
  }

  override_data {
    target = module.diagnostics.data.aws_ami.dr
    values = {
      id   = "image-not-an-ami"
      name = "bad-image"
    }
  }

  expect_failures = [output.diagnostic_guard]
}

run "invalid_account_is_rejected" {
  command = plan

  variables {
    name_prefix = "mock-c34"
  }

  override_data {
    target = module.diagnostics.data.aws_caller_identity.dr
    values = {
      account_id = "not-an-account"
      arn        = "arn:aws:iam::222222222222:role/dr-runner"
      user_id    = "dr-runner"
    }
  }

  expect_failures = [output.diagnostic_guard]
}

run "empty_session_issuer_is_rejected" {
  command = plan

  variables {
    name_prefix = "mock-c34"
  }

  override_data {
    target = module.diagnostics.data.aws_iam_session_context.dr
    values = {
      issuer_arn = ""
    }
  }

  expect_failures = [output.diagnostic_guard]
}

run "invalid_session_issuer_is_rejected" {
  command = plan

  variables {
    name_prefix = "mock-c34"
  }

  override_data {
    target = module.diagnostics.data.aws_iam_session_context.dr
    values = {
      issuer_arn = "not-an-iam-arn"
    }
  }

  expect_failures = [output.diagnostic_guard]
}
