run "dual_provider_routes_are_real" {
  command = plan

  assert {
    condition = (
      output.routing_contract.primary.route == "primary" &&
      output.routing_contract.primary.region == "us-east-1" &&
      output.routing_contract.primary.subnet_id == var.primary_subnet_id &&
      output.routing_contract.audit.route == "audit" &&
      output.routing_contract.audit.region == "us-west-2" &&
      output.routing_contract.audit.subnet_id == var.audit_subnet_id &&
      can(regex("^ami-[0-9a-f]{8,17}$", output.routing_contract.primary.ami_id)) &&
      can(regex("^ami-[0-9a-f]{8,17}$", output.routing_contract.audit.ami_id))
    )
    error_message = "Real AMI/subnet data did not follow the explicit provider routes."
  }
}

run "catalog_reorder_is_semantically_stable" {
  command = plan
  variables { catalog_path = "../fixtures/routes-reordered.json" }
  assert {
    condition     = output.routing_contract.catalog_fingerprint == sha256(jsonencode({ audit = "security", primary = "platform" }))
    error_message = "Route catalog order changed the semantic contract."
  }
}

run "invalid_owner_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/routes-invalid-owner.json" }
  expect_failures = [aws_iam_role.workload]
}

run "invalid_schema_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/routes-invalid-schema.json" }
  expect_failures = [aws_iam_role.workload]
}

run "duplicate_route_is_rejected" {
  command = plan
  variables { catalog_path = "../fixtures/routes-duplicate.json" }
  expect_failures = [aws_iam_role.workload]
}

run "unsupported_instance_type_is_rejected" {
  command = plan
  variables { instance_type = "m7i.48xlarge" }
  expect_failures = [var.instance_type]
}

run "public_endpoint_is_rejected" {
  command = plan
  variables { localstack_endpoint = "https://aws.amazon.com:443" }
  expect_failures = [var.localstack_endpoint]
}

run "invalid_run_id_is_rejected" {
  command = plan
  variables { run_id = "BAD" }
  expect_failures = [var.run_id]
}
