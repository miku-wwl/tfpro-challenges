resource "random_id" "release" {
  for_each = var.release_channels

  byte_length = 4
  keepers = {
    service         = var.service_name
    channel         = each.key
    contract_schema = "2"
  }
}
