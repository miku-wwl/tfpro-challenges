mock_provider "aws" {
  alias = "primary"

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
      arn        = "arn:aws:iam::000000000000:user/primary"
      user_id    = "primary"
    }
  }

  mock_data "aws_region" {
    defaults = { name = "us-east-1" }
  }
}

mock_provider "aws" {
  alias = "dr"

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
      arn        = "arn:aws:iam::000000000000:user/dr"
      user_id    = "dr"
    }
  }

  mock_data "aws_region" {
    defaults = { name = "us-west-2" }
  }
}

mock_provider "aws" {
  alias = "audit"

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
      arn        = "arn:aws:iam::000000000000:user/audit"
      user_id    = "audit"
    }
  }

  mock_data "aws_region" {
    defaults = { name = "us-east-2" }
  }
}

run "provider_slots_are_distinct" {
  command = plan

  variables {
    name_prefix = "mock-c24"
  }

  assert {
    condition = output.provider_diagnostics == {
      primary = { account_id = "000000000000", region = "us-east-1" }
      dr      = { account_id = "000000000000", region = "us-west-2" }
      audit   = { account_id = "000000000000", region = "us-east-2" }
    }
    error_message = "provider slot 的 caller/region 诊断不匹配。"
  }

  assert {
    condition = (
      output.resource_contract.primary_bucket == "mock-c24-primary" &&
      output.resource_contract.dr_bucket == "mock-c24-dr"
    )
    error_message = "双区域 bucket 合同不稳定。"
  }
}
