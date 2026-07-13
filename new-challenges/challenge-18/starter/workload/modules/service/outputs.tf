output "profile" {
  value = {
    deployment_key = var.deployment_key
    service        = var.service.name
    owner          = var.service.owner
    location       = var.service.location
    region         = var.network.region
    port           = var.service.port
  }
}

