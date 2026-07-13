resource "terraform_data" "service" {
  count = length(var.services)

  input = {
    name        = var.services[count.index].name
    port        = var.services[count.index].port
    owner       = var.services[count.index].owner
    tier        = var.services[count.index].tier
    environment = var.environment
    tags        = var.common_tags
  }
}

