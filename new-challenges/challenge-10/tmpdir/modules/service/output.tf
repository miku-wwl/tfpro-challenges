output "contract_version" {
  value = 2
}

output "manifest" {
  value = {
    name        = var.service.name
    port        = var.service.port
    owner       = var.service.owner
    tier        = var.service.tier
    environment = var.context.environment
    tags        = var.context.tags
  }
}

output "healthcheck" {
  value = var.service.healthcheck
}