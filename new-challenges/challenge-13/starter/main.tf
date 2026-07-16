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
      condition     = tonumber(each.value.port) > 0 && tonumber(each.value.port) <= 65535 && contains(keys(local.owners), each.value.owner) && contains(var.policy.allowed_tiers, each.value.tier)
      error_message = "Each service row must satisfy the deployment contract."
    }

    postcondition {
      condition     = self.output.endpoint  == "${lower(each.key)}:${each.value.port}"
      error_message = "The generated endpoint is not normalized."
    }
  }
}

check "capacity_budget" {
  assert {
    condition     = (
      sum([
        for service in local.services : service.capacity
      ]) <= var.policy.max_total_capacity
    )

    error_message = "Selected services exceed max_total_capacity."
  }
}
