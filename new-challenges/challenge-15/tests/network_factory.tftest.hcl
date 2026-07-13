mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = {
      id         = "vpc-0123456789abcdef0"
      cidr_block = "10.42.0.0/16"
    }
  }

  mock_data "aws_subnet" {
    defaults = {
      id = "subnet-0123456789abcdef0"
    }
  }
}

run "prod_catalog" {
  command = plan

  assert {
    condition     = jsonencode(output.service_names) == jsonencode(["admin", "api", "worker"])
    error_message = "Only enabled prod services should create security groups."
  }

  assert {
    condition     = length(output.ingress_rule_keys) == 3 && length(output.egress_rule_keys) == 2
    error_message = "Expected three ingress and two egress prod rules."
  }

  assert {
    condition     = length(output.rules_by_owner.platform) == 2 && length(output.rules_by_owner.data) == 2 && length(output.rules_by_owner.security) == 1
    error_message = "Rules must be grouped by owner after filtering."
  }

  assert {
    condition     = jsonencode(sort(keys(output.subnet_ids))) == jsonencode(["app", "data"])
    error_message = "Both requested subnet tiers must be queried with stable keys."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["worker|prod|ingress|tcp|09100|09100|vpc"].cidr_ipv4 == "10.42.0.0/16"
    error_message = "The vpc source alias must resolve to the queried VPC CIDR."
  }
}

run "reordered_catalog" {
  command = plan

  variables {
    rules_file = "../fixtures/rules-reordered.csv"
  }

  assert {
    condition = jsonencode(output.ingress_rule_keys) == jsonencode([
      "admin|prod|ingress|tcp|00022|00022|office",
      "api|prod|ingress|tcp|00443|00443|office",
      "worker|prod|ingress|tcp|09100|09100|vpc",
    ])
    error_message = "Reordering CSV rows must not alter ingress resource identities."
  }

  assert {
    condition = jsonencode(output.egress_rule_keys) == jsonencode([
      "api|prod|egress|tcp|00443|00443|0.0.0.0/0",
      "worker|prod|egress|tcp|05432|05432|vpc",
    ])
    error_message = "Reordering CSV rows must not alter egress resource identities."
  }
}

run "reject_unknown_environment" {
  command = plan

  variables {
    target_environment = "qa"
  }

  expect_failures = [var.target_environment]
}
