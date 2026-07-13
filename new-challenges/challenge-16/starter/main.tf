locals {
  catalog = jsondecode(file(var.catalog_file))
  enabled = [for service in local.catalog : service if service.enabled]

  # TODO: 行号会在 catalog 重排后改变资源身份，改用 service.name。
  services_by_key = {
    for index, service in local.enabled : tostring(index) => service
  }
}

resource "terraform_data" "service" {
  for_each = local.services_by_key

  input = {
    name        = each.value.name
    owner       = each.value.owner
    tier        = each.value.tier
    environment = var.environment
  }
}

resource "local_file" "inventory" {
  filename = "${path.module}/generated-inventory.json"
  content = jsonencode({
    environment = var.environment
    services = {
      for key, resource in terraform_data.service : key => resource.output
    }
  })
}

