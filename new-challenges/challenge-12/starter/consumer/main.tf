locals {
  # TODO: select the producer's network_contract output.
  network_contract = {
    schema_version = 0
    environment    = "unknown"
    subnets        = {}
  }
}

resource "terraform_data" "application" {
  # TODO: use stable service keys from the remote-state contract.
  for_each = {}

  input = {
    service     = each.key
    environment = local.network_contract.environment
    subnet_cidr = each.value
  }

  lifecycle {
    precondition {
      condition     = local.network_contract.schema_version == 1
      error_message = "The consumer requires network contract schema version 1."
    }
  }
}
