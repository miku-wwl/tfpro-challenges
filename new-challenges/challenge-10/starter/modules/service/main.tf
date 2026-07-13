resource "terraform_data" "this" {
  input = {
    name        = var.name
    port        = var.port
    owner       = var.owner
    tier        = var.tier
    environment = var.environment
    tags        = var.tags
  }
}
