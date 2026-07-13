mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.42.0.0/16"
    }
  }

  mock_data "aws_subnet" {
    defaults = {
      cidr_block = "10.42.99.0/24"
    }
  }
}

run "canonical_csv_contract" {
  command = plan

  variables {
    name_prefix    = "tfpro-c21-mock"
    rules_csv_path = "../fixtures/rules.csv"
  }

  assert {
    condition     = output.active_rule_ids == tolist(["api-from-web", "db-from-api", "dns-from-data", "metrics-from-private", "web-from-public"])
    error_message = "Only enabled prod rule IDs must survive, sorted by stable identity"
  }

  assert {
    condition     = output.rules_by_owner.edge == tolist(["web-from-public"]) && output.rules_by_owner.platform == tolist(["api-from-web", "metrics-from-private"]) && output.rules_by_owner.data == tolist(["db-from-api", "dns-from-data"])
    error_message = "Owner grouping must be deterministic"
  }

  assert {
    condition     = output.topology_contract.rule_count == 5
    error_message = "Exactly five enabled production rules are expected"
  }
}

run "reordered_csv_contract" {
  command = plan

  variables {
    name_prefix    = "tfpro-c21-mock"
    rules_csv_path = "../fixtures/rules-reordered.csv"
  }

  assert {
    condition     = output.active_rule_ids == tolist(["api-from-web", "db-from-api", "dns-from-data", "metrics-from-private", "web-from-public"])
    error_message = "CSV row ordering must not affect identities"
  }

  assert {
    condition     = output.resource_addresses.rules == tolist(["aws_vpc_security_group_ingress_rule.this[\"api-from-web\"]", "aws_vpc_security_group_ingress_rule.this[\"db-from-api\"]", "aws_vpc_security_group_ingress_rule.this[\"dns-from-data\"]", "aws_vpc_security_group_ingress_rule.this[\"metrics-from-private\"]", "aws_vpc_security_group_ingress_rule.this[\"web-from-public\"]"])
    error_message = "Rule addresses must use rule_id rather than row indexes"
  }
}

run "invalid_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "unknown_subnet_reference" {
  command = plan

  variables {
    rules_csv_path = "../fixtures/rules-invalid-subnet.csv"
  }

  expect_failures = [check.rule_subnets_exist]
}
