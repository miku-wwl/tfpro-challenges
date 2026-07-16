output "service_ports" {
  value = { for service in var.services : service.name => service.port }
}

