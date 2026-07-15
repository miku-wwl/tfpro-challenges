run "remote_contract_drives_ec2_release" {
  command = plan
  assert {
    condition = (
      output.deployment_contract.revision == var.expected_revision &&
      output.deployment_contract.node_keys == tolist(["api", "worker"]) &&
      output.deployment_contract.image_id == data.aws_ami.selected.id &&
      output.deployment_contract.subnet_id == var.subnet_id &&
      output.deployment_contract.artifact_digests.api == sha256("api artifact v1") &&
      output.deployment_contract.artifact_digests.worker == sha256("worker artifact v1")
    )
    error_message = "The remote artifact contract did not drive the exact EC2 deployment."
  }
}

run "deployment_reorder_is_address_stable" {
  command = plan
  variables { manifest_path = "../../fixtures/deployments-reordered.json" }
  assert {
    condition     = output.deployment_contract.node_keys == tolist(["api", "worker"])
    error_message = "Deployment order changed stable node identity."
  }
}

run "duplicate_node_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/deployments-duplicate.json" }
  expect_failures = [aws_security_group.runtime]
}

run "unknown_artifact_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/deployments-unknown-artifact.json" }
  expect_failures = [aws_security_group.runtime]
}

run "invalid_manifest_shape_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/deployments-invalid-shape.json" }
  expect_failures = [aws_security_group.runtime]
}

run "invalid_instance_type_is_rejected" {
  command = plan
  variables { manifest_path = "../../fixtures/deployments-invalid-instance-type.json" }
  expect_failures = [aws_security_group.runtime]
}

run "stale_revision_is_rejected" {
  command = plan
  variables { expected_revision = "2026.07.9" }
  expect_failures = [aws_security_group.runtime]
}

run "wrong_publisher_state_key_is_rejected" {
  command = plan
  variables { publisher_state_key = "wrong/terraform.tfstate" }
  expect_failures = [var.publisher_state_key]
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
