locals {
  service_names = sort(keys(var.catalog))
  manifest_content = jsonencode({
    services = var.catalog
  })
}

resource "terraform_data" "service" {
  for_each = toset(local.service_names)

  input = merge(var.catalog[each.value], {
    name = each.value
  })
}

moved {
  from = terraform_data.workload[0]
  to   = terraform_data.service["api"]
}

moved {
  from = terraform_data.workload[1]
  to   = terraform_data.service["web"]
}

moved {
  from = terraform_data.workload[2]
  to   = terraform_data.service["worker"]
}

resource "local_file" "manifest" {
  filename        = var.manifest_path
  content         = local.manifest_content
  file_permission = "0644"

  lifecycle {
    create_before_destroy = true
  }
}

moved {
  from = local_file.inventory
  to   = local_file.manifest
}

resource "terraform_data" "guardian" {
  input = {
    name   = "ops-guardian"
    policy = "retain"
  }

  lifecycle {
    prevent_destroy = true
  }
}

import {
  to = terraform_data.guardian
  id = "ops-guardian-v1"
}