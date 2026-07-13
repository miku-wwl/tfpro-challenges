mock_provider "aws" {
  alias = "mock_primary"

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
      arn        = "arn:aws:iam::111111111111:role/TerraformPrimary"
      user_id    = "AROAPRIMARY:terraform-test"
    }
  }
}

mock_provider "aws" {
  alias = "mock_recovery"

  mock_data "aws_region" {
    defaults = {
      name = "us-west-2"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "222222222222"
      arn        = "arn:aws:iam::222222222222:role/TerraformRecoveryReadWrite"
      user_id    = "AROARECOVERY:terraform-test"
    }
  }
}

run "provider_slots_are_explicit" {
  command = plan

  providers = {
    aws          = aws.mock_primary
    aws.recovery = aws.mock_recovery
  }

  assert {
    condition = output.provider_regions == {
      primary  = "us-east-1"
      recovery = "us-west-2"
    }
    error_message = "primary/recovery provider region 被继承或交换。"
  }

  assert {
    condition = output.caller_accounts == {
      primary  = "111111111111"
      recovery = "222222222222"
    }
    error_message = "两个 provider slot 必须使用不同的 caller identity。"
  }

  assert {
    condition     = output.bucket_names.primary == "tfpro-alias-primary" && output.bucket_names.recovery == "tfpro-alias-recovery"
    error_message = "bucket naming contract 不正确。"
  }
}

