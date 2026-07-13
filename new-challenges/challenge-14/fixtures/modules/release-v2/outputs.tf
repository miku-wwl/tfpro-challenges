output "manifest" {
  value = {
    schema_version = 2
    service_name   = var.service_name
    artifacts      = { for channel, release in random_id.release : channel => release.hex }
  }
}
