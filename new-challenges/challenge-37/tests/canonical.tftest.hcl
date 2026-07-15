run "canonical_ingress_contract" {
  command = plan
  variables { name_prefix = "tfpro-c37-plan" }
  assert {
    condition     = length(output.active_rule_keys) == 3
    error_message = "Only three enabled ingress rules may enter the graph."
  }
  assert {
    condition     = length(output.resource_addresses.ingress) == 3
    error_message = "Every enabled row must map to an independent ingress resource."
  }
  assert {
    condition     = output.security_contract.rules["tcp|00443-00443|10.10.0.0_16"].rule_id == "web-tls"
    error_message = "The stable tuple key does not match rule semantics."
  }
}

run "reordered_csv_is_stable" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-reordered.csv" }
  assert {
    condition     = length(output.active_rule_keys) == 3 && output.active_rule_keys[0] == "tcp|00022-00022|10.20.0.0_24"
    error_message = "CSV reorder changed stable keys."
  }
}

run "duplicate_rule_id_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-duplicate-id.csv" }
  expect_failures = [check.rule_ids_unique, aws_security_group.rules]
}
run "duplicate_tuple_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-duplicate-tuple.csv" }
  expect_failures = [check.rule_keys_unique, aws_security_group.rules]
}
run "empty_rule_id_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-fields.csv" }
  expect_failures = [check.rule_ids_valid, aws_security_group.rules]
}
run "invalid_protocol_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-protocol.csv" }
  expect_failures = [check.rule_protocols_valid, aws_security_group.rules]
}
run "empty_description_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-empty-description.csv" }
  expect_failures = [check.rule_descriptions_valid, aws_security_group.rules]
}
run "invalid_enabled_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-enabled.csv" }
  expect_failures = [check.rule_enabled_values_valid, check.rules_not_empty, aws_security_group.rules]
}
run "invalid_ports_are_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-ports.csv" }
  expect_failures = [check.rule_ports_valid, aws_security_group.rules]
}
run "invalid_cidr_is_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-invalid-cidr.csv" }
  expect_failures = [check.rule_cidrs_valid, aws_security_group.rules]
}
run "empty_rules_are_rejected" {
  command = plan
  variables { rules_csv_path = "../fixtures/rules-empty.csv" }
  expect_failures = [check.rules_not_empty, aws_security_group.rules]
}
run "non_loopback_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com" }
  expect_failures = [var.localstack_endpoint]
}
