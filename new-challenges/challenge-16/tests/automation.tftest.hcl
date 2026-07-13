run "stable_service_identity" {
  command = apply

  assert {
    condition     = jsonencode(output.service_names) == jsonencode(["api", "worker"])
    error_message = "Only enabled services should remain, sorted by business name."
  }

  assert {
    condition = jsonencode(output.service_addresses) == jsonencode([
      "terraform_data.service[\"api\"]",
      "terraform_data.service[\"worker\"]",
    ])
    error_message = "terraform_data resources must use service name as their stable for_each key."
  }

  assert {
    condition     = jsondecode(local_file.inventory.content).services.api.owner == "platform"
    error_message = "Generated inventory must remain machine-readable and keyed by service."
  }
}

run "reordered_catalog_keeps_addresses" {
  command = plan

  variables {
    catalog_file = "../fixtures/services-reordered.json"
  }

  assert {
    condition = jsonencode(output.service_addresses) == jsonencode([
      "terraform_data.service[\"api\"]",
      "terraform_data.service[\"worker\"]",
    ])
    error_message = "Reordering input must not alter resource addresses."
  }
}

run "reject_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}
