mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "000000000000" }
  }
  mock_data "aws_vpc" {
    defaults = { id = "vpc-0123456789abcdef0" }
  }
  mock_data "aws_security_group" {
    defaults = { id = "sg-0123456789abcdef0" }
  }
}

run "canonical_rule_contract" {
  command = plan
  variables { name_prefix = "tfpro-c37-mock" }
  assert {
    condition     = length(output.active_rule_keys) == 4
    error_message = "只允许四条 enabled rules 进入 graph。"
  }
  assert {
    condition     = length(output.resource_addresses.ingress) == 3 && length(output.resource_addresses.egress) == 1
    error_message = "ingress/egress 必须编译为独立资源。"
  }
  assert {
    condition     = output.security_contract.rules["ingress|tcp|00443-00443|10.10.0.0_16"].rule_id == "web-tls"
    error_message = "复合 key 与规则语义不匹配。"
  }
}

run "reordered_csv_is_stable" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-reordered.csv" }
  assert {
    condition     = length(output.active_rule_keys) == 4 && output.active_rule_keys[0] == "egress|tcp|00443-00443|0.0.0.0_0"
    error_message = "CSV 重排不得改变规范化 keys。"
  }
}

run "duplicate_rule_id_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-duplicate-id.csv" }
  expect_failures = [check.rule_ids_unique]
}

run "duplicate_tuple_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-duplicate-tuple.csv" }
  expect_failures = [check.rule_keys_unique]
}

run "overlapping_range_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-overlap.csv" }
  expect_failures = [check.rule_ranges_nonoverlapping]
}

run "empty_rule_id_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-fields.csv" }
  expect_failures = [check.rule_ids_valid]
}

run "invalid_direction_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-direction.csv" }
  expect_failures = [check.rule_directions_valid]
}

run "invalid_protocol_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-protocol.csv" }
  expect_failures = [check.rule_protocols_valid]
}

run "empty_description_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-empty-description.csv" }
  expect_failures = [check.rule_descriptions_valid]
}

run "invalid_enabled_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-enabled.csv" }
  expect_failures = [check.rule_enabled_values_valid]
}

run "invalid_ports_are_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-ports.csv" }
  expect_failures = [check.rule_ports_valid]
}

run "invalid_cidr_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-cidr.csv" }
  expect_failures = [check.rule_cidrs_valid]
}

run "empty_rules_are_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-empty.csv" }
  expect_failures = [check.rules_not_empty]
}

run "non_loopback_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com" }
  expect_failures = [var.localstack_endpoint]
}
