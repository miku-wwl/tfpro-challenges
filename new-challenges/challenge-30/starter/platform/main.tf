data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "${path.module}/${var.foundation_state_path}"
  }
}

locals {
  network = data.terraform_remote_state.foundation.outputs.network_contract
}

resource "terraform_data" "contract_guard" {
  input = try(local.network.contract_version, 0)

  lifecycle {
    # TODO: Require contract version 1 and matching primary/DR regions.
    precondition {
      condition     = try(local.network.contract_version, 0) >= 0
      error_message = "Complete the upstream network contract guard."
    }
  }
}

resource "aws_security_group" "primary" {
  name        = "${var.run_id}-primary-workloads"
  description = "Primary workload boundary"
  vpc_id      = local.network.primary.vpc_id
  tags        = { Role = "primary" }
}

resource "aws_sns_topic" "primary" {
  name = "${var.run_id}-primary-events"
  tags = { Role = "primary" }
}

resource "aws_dynamodb_table" "primary" {
  name         = "${var.run_id}-primary-catalog"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = { Role = "primary" }
}

resource "aws_security_group" "dr" {
  # TODO: All DR platform resources are currently routed to primary.
  name        = "${var.run_id}-dr-workloads"
  description = "DR workload boundary"
  vpc_id      = local.network.dr.vpc_id
  tags        = { Role = "dr" }
}

resource "aws_sns_topic" "dr" {
  name = "${var.run_id}-dr-events"
  tags = { Role = "dr" }
}

resource "aws_dynamodb_table" "dr" {
  name         = "${var.run_id}-dr-catalog"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = { Role = "dr" }
}
