locals {
  catalog = jsondecode(file(var.catalog_file))

  # TODO 1: normalize the catalog and key enabled services by semantic name.
  services = {}

  canonical_inventory = {
    environment = var.environment
    services    = [for name in sort(keys(local.services)) : local.services[name]]
  }
}

check "catalog_not_empty" {
  assert {
    condition     = length(local.catalog) > 0
    error_message = "The catalog must not be empty."
  }
}

check "service_names_unique" {
  assert {
    # TODO 2: reject duplicate names independently.
    condition     = true
    error_message = "Service names must be unique."
  }
}

check "service_fields_valid" {
  assert {
    # TODO 3: validate name, owner, tier, and boolean enabled fields.
    condition     = true
    error_message = "Every service must satisfy the inventory schema."
  }
}

check "enabled_services_present" {
  assert {
    condition     = length(local.services) > 0
    error_message = "At least one enabled service is required."
  }
}

resource "aws_s3_bucket" "inventory" {
  bucket        = "${var.name_prefix}-${var.environment}-inventory"
  force_destroy = true
  tags          = { ManagedBy = "terraform", Challenge = "16", Environment = var.environment }
}

resource "aws_s3_object" "service" {
  for_each = local.services

  bucket       = aws_s3_bucket.inventory.id
  key          = "services/${each.key}.json"
  content      = jsonencode(each.value)
  content_type = "application/json"
  # TODO 4: add etag, metadata, and the required deterministic tags.
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.inventory.id
  key          = "inventory/index.json"
  content      = jsonencode(local.canonical_inventory)
  content_type = "application/json"
  etag         = md5(jsonencode(local.canonical_inventory))
  tags         = { ManagedBy = "terraform", Kind = "index", Environment = var.environment }
}
