resource "random_id" "release" {
  for_each = toset(var.channels)

  byte_length = 4
  keepers = {
    name    = var.name
    channel = each.key
  }
}
