resource "terraform_data" "service" {
  input = {
    name        = var.service.name
    port        = var.service.port
    owner       = var.service.owner
    tier        = var.service.tier
    environment = var.environment
    tags        = var.common_tags
  }
}