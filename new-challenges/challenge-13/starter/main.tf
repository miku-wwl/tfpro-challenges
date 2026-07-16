locals {
  owners = jsondecode(file("${path.module}/${var.owners_file}"))
  rows   = csvdecode(file("${path.module}/${var.services_file}"))

  services = {
    for row in local.rows : row.name => {
      name        = row.name
      environment = row.environment
      owner       = row.owner
      port        = tonumber(row.port)
      enabled     = tobool(row.enabled)
      tier        = row.tier
      capacity    = tonumber(row.capacity)
    } if row.environment == var.target_environment && tobool(row.enabled)
  }
}

resource "terraform_data" "service" {
  for_each = local.services

  input = {
    name     = each.key
    owner    = each.value.owner
    port     = each.value.port
    tier     = each.value.tier
    capacity = each.value.capacity
    endpoint = "${lower(each.key)}:${each.value.port}"
  }

  lifecycle {
    precondition {
      # TODO: also enforce the upper port bound, known owner, and allowed tier.
      condition     = tonumber(each.value.port) > 0
      error_message = "Each service row must satisfy the deployment contract."
    }

    postcondition {
      # TODO: verify the normalized endpoint contract.
      condition     = self.output.name == each.key
      error_message = "The generated endpoint is not normalized."
    }
  }
}

check "capacity_budget" {
  assert {
    # TODO: aggregate typed capacity across all selected services.
    condition     = length(local.services) > 0
    error_message = "Selected services exceed max_total_capacity."
  }
}
