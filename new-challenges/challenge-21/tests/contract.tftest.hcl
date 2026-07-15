run "canonical_csv_contract" {
  command = plan

  assert {
    condition     = join(",", output.active_rule_ids) == "api-from-web,db-from-api,dns-from-data,metrics-from-private,web-from-public"
    error_message = "Only enabled target-environment rules may enter the graph."
  }

  assert {
    condition = (
      length(output.resource_addresses.groups) == 3 &&
      length(output.resource_addresses.rules) == 5 &&
      output.topology_contract.rule_count == 5
    )
    error_message = "The canonical managed address contract is incomplete."
  }

  assert {
    condition = (
      output.topology_contract.subnet_cidrs["public-a"] == "10.42.10.0/24" &&
      output.topology_contract.subnet_cidrs["private-a"] == "10.42.20.0/24" &&
      output.topology_contract.subnet_cidrs["data-a"] == "10.42.30.0/24"
    )
    error_message = "Subnet CIDRs must come from provider data sources."
  }
}

run "owner_groups_are_stable" {
  command = plan

  assert {
    condition = (
      join(",", output.rules_by_owner.edge) == "web-from-public" &&
      join(",", output.rules_by_owner.platform) == "api-from-web,metrics-from-private" &&
      join(",", output.rules_by_owner.data) == "db-from-api,dns-from-data"
    )
    error_message = "Owner grouping must be deterministic."
  }
}

run "reordered_csv_contract" {
  command = plan

  variables {
    rules_csv_path = "../fixtures/rules-reordered.csv"
  }

  assert {
    condition     = join(",", output.active_rule_ids) == "api-from-web,db-from-api,dns-from-data,metrics-from-private,web-from-public"
    error_message = "CSV reorder must preserve logical identity."
  }
}

run "dev_environment_filters_before_graph" {
  command = plan

  variables {
    environment = "dev"
  }

  assert {
    condition     = join(",", output.active_rule_ids) == "dev-web"
    error_message = "Environment filtering must occur before graph construction."
  }
}

run "reject_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "reject_duplicate_rule_id" {
  command = plan

  variables {
    rules_csv_path = "../fixtures/rules-duplicate-id.csv"
  }

  expect_failures = [output.active_rule_ids]
}

run "reject_unknown_subnet_reference" {
  command = plan

  variables {
    rules_csv_path = "../fixtures/rules-invalid-subnet.csv"
  }

  expect_failures = [output.active_rule_ids]
}

run "reject_invalid_protocol_and_ports" {
  command = plan

  variables {
    rules_csv_path = "../fixtures/rules-invalid-port-protocol.csv"
  }

  expect_failures = [output.active_rule_ids]
}

run "reject_security_group_owner_conflict" {
  command = plan

  variables {
    rules_csv_path = "../fixtures/rules-owner-conflict.csv"
  }

  expect_failures = [output.active_rule_ids]
}

run "reject_public_endpoint" {
  command = plan

  variables {
    localstack_endpoint = "https://ec2.amazonaws.com:443"
  }

  expect_failures = [var.localstack_endpoint]
}
