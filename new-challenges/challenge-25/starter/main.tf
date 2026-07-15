locals {
  config           = jsondecode(file(var.config_path))
  canonical_config = jsonencode(local.config)
  config_sha256    = sha256(local.canonical_config)
  revision_id      = "v${var.config_version}-${local.config_sha256}"
  bucket_name      = "${var.name_prefix}-${var.environment}-config"
}

resource "aws_s3_bucket" "config" {
  bucket = local.bucket_name

  tags = {
    Challenge = "25"
    ManagedBy = "terraform"
    RunId     = var.name_prefix
    Role      = "config"
  }
}

# TODO: publish one immutable revision object with a revision_id keyed for_each map.
# TODO: publish one stable revision-pointer object that changes with revision identity.

resource "aws_s3_object" "current" {
  bucket = aws_s3_bucket.config.id
  key    = "config/current.json"

  # TODO: publish canonical JSON with etag/source_hash/tags.
  # TODO: add contract preconditions, content-type postcondition,
  # and replace_triggered_by the stable revision-pointer resource.
}
