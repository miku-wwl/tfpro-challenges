output "legacy_release" {
  value = {
    name = var.name
    ids  = { for channel, release in random_id.release : channel => release.hex }
  }
}
