mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
      arn        = "arn:aws:iam::000000000000:root"
      user_id    = "AIDATEST"
    }
  }

  mock_data "aws_ami" {
    defaults = {
      id           = "ami-0123456789abcdef0"
      architecture = "x86_64"
    }
  }
}

run "sensitive_identity_contract" {
  command = plan

  variables {
    name_prefix = "tfpro-c32-mock"
    bootstrap = {
      api_token         = "canonical-api-token"
      database_password = "canonical-database-password"
      feature_flags = {
        metrics = true
        tracing = false
      }
    }
  }

  assert {
    condition     = length(output.bootstrap_digest) == 64 && can(regex("^[0-9a-f]{64}$", output.bootstrap_digest))
    error_message = "只应公开稳定的 SHA-256 digest。"
  }

  assert {
    condition = (
      output.identity_contract.permission_actions == tolist(jsondecode(file("../fixtures/expected-boundary.json")).actions) &&
      alltrue([
        for arn in output.identity_contract.parameter_arns :
        startswith(arn, jsondecode(file("../fixtures/expected-boundary.json")).resource_prefix)
      ])
    )
    error_message = "权限 action/parameter namespace 必须精确匹配 expected-boundary fixture。"
  }

  assert {
    condition     = output.identity_contract.account_id == "000000000000"
    error_message = "identity contract 必须来自 caller identity。"
  }
}

run "feature_flag_map_is_deterministic" {
  command = plan

  variables {
    name_prefix = "tfpro-c32-mock"
    bootstrap = {
      api_token         = "canonical-api-token"
      database_password = "canonical-database-password"
      feature_flags = {
        tracing = false
        metrics = true
      }
    }
  }

  assert {
    condition = output.bootstrap_digest == nonsensitive(sha256(templatefile("../fixtures/bootstrap.sh.tftpl", {
      api_token          = "canonical-api-token"
      database_password  = "canonical-database-password"
      feature_flags_json = jsonencode({ metrics = true, tracing = false })
    })))
    error_message = "map 输入顺序不能改变渲染 digest。"
  }
}

run "short_bootstrap_secret" {
  command = plan

  variables {
    bootstrap = {
      api_token         = "short"
      database_password = "also-short"
      feature_flags     = {}
    }
  }

  expect_failures = [var.bootstrap]
}

run "wildcard_identity_boundary" {
  command = plan

  variables {
    identity_boundary = {
      role_path              = "/tfpro/"
      allowed_parameter_arns = ["arn:aws:ssm:us-east-1:000000000000:parameter/tfpro/*"]
    }
  }

  expect_failures = [check.identity_boundary_scoped]
}

run "missing_user_data_template" {
  command = plan

  variables {
    user_data_template_path = "../fixtures/missing-bootstrap.sh.tftpl"
  }

  expect_failures = [var.user_data_template_path]
}

run "non_loopback_candidate_endpoint" {
  command = plan

  variables {
    localstack_endpoint = "https://aws.amazon.com"
  }

  expect_failures = [var.localstack_endpoint]
}

run "empty_identity_boundary" {
  command = plan

  variables {
    identity_boundary = {
      role_path              = "/tfpro/"
      allowed_parameter_arns = []
    }
  }

  expect_failures = [check.identity_boundary_scoped]
}

run "outside_tfpro_namespace" {
  command = plan

  variables {
    identity_boundary = {
      role_path              = "/tfpro/"
      allowed_parameter_arns = ["arn:aws:ssm:us-east-1:000000000000:parameter/other/secret"]
    }
  }

  expect_failures = [check.identity_boundary_scoped]
}
