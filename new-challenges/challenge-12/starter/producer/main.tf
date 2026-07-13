locals {
  rows = csvdecode(file(var.services_file))

  # TODO: filter enabled rows for var.environment, convert subnet_slot to number,
  # and key this map by the stable service name (not the CSV row index).
  services = {
    for index, row in local.rows : tostring(index) => row
  }
}

resource "terraform_data" "network" {
  for_each = local.services

  input = {
    service     = each.value.service
    subnet_cidr = "10.42.${each.value.subnet_slot}.0/24"
  }
}
