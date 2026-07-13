mock_provider "aws" {
  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-primary"
    }
  }

  mock_resource "aws_vpc_security_group_ingress_rule" {
    defaults = {
      id = "sgr-primary"
    }
  }
}

mock_provider "aws" {
  alias = "dr"

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-dr"
    }
  }

  mock_resource "aws_vpc_security_group_ingress_rule" {
    defaults = {
      id = "sgr-dr"
    }
  }
}

run "default_catalog_is_filtered_expanded_and_stable" {
  command = plan

  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        network_contract = {
          primary = {
            vpc_id    = "vpc-primary"
            subnet_id = "subnet-primary"
            region    = "us-east-1"
          }
          dr = {
            vpc_id    = "vpc-dr"
            subnet_id = "subnet-dr"
            region    = "us-west-2"
          }
        }
      }
    }
  }

  assert {
    condition = join(",", output.deployment_keys) == join(",", [
      "api@primary", "metrics@dr", "metrics@primary", "worker@dr"
    ])
    error_message = "Enabled prod services must expand into stable service@location keys."
  }

  assert {
    condition = join(",", output.deployment_addresses) == join(",", [
      "module.service_primary[\"api@primary\"].aws_security_group.service",
      "module.service_dr[\"metrics@dr\"].aws_security_group.service",
      "module.service_primary[\"metrics@primary\"].aws_security_group.service",
      "module.service_dr[\"worker@dr\"].aws_security_group.service",
    ])
    error_message = "Module addresses must expose the correct static provider branch."
  }

  assert {
    condition = (
      join(",", output.deployments_by_owner.platform) == "api@primary" &&
      join(",", output.deployments_by_owner.data) == "worker@dr" &&
      join(",", output.deployments_by_owner.observability) == "metrics@dr,metrics@primary"
    )
    error_message = "Deployment owner groups must contain only selected, sorted keys."
  }
}

run "reordered_catalog_preserves_identity" {
  command = plan

  variables {
    catalog_file = "../../fixtures/services-reordered.csv"
  }

  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        network_contract = {
          primary = {
            vpc_id    = "vpc-primary"
            subnet_id = "subnet-primary"
            region    = "us-east-1"
          }
          dr = {
            vpc_id    = "vpc-dr"
            subnet_id = "subnet-dr"
            region    = "us-west-2"
          }
        }
      }
    }
  }

  assert {
    condition = join(",", output.deployment_keys) == join(",", [
      "api@primary", "metrics@dr", "metrics@primary", "worker@dr"
    ])
    error_message = "CSV row order must not affect resource identity."
  }
}

run "unknown_environment_is_rejected" {
  command = plan

  variables {
    target_environment = "qa"
  }

  override_data {
    target = data.terraform_remote_state.foundation
    values = {
      outputs = {
        network_contract = {
          primary = {
            vpc_id    = "vpc-primary"
            subnet_id = "subnet-primary"
            region    = "us-east-1"
          }
          dr = {
            vpc_id    = "vpc-dr"
            subnet_id = "subnet-dr"
            region    = "us-west-2"
          }
        }
      }
    }
  }

  expect_failures = [
    var.target_environment,
  ]
}
