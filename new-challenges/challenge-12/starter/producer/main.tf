locals {
  rows = csvdecode(file(var.services_file))

  # TODO 1: normalize the CSV, select enabled rows for environment, and use service names as stable keys.
  services = {
    for index, row in local.rows : tostring(index) => row
  }
}

resource "aws_s3_bucket" "release" {
  bucket        = "${var.name_prefix}-producer"
  force_destroy = true
  tags          = { ManagedBy = "terraform", Challenge = "12", Role = "producer" }
}

resource "aws_s3_object" "service" {
  for_each = local.services

  bucket       = aws_s3_bucket.release.id
  key          = "services/${each.key}.json"
  content      = jsonencode(each.value)
  content_type = "application/json"
  # TODO 2: add an MD5 etag so declared content drift is repairable.
}

check "enabled_services_exist" {
  assert {
    condition     = length(local.services) > 0
    error_message = "At least one enabled service is required."
  }
}
