locals {
  manifest_raw = file(var.manifest_path)
  manifest     = jsondecode(local.manifest_raw)
  digest       = sha256(local.manifest_raw)
}

# TODO: manifest_contract check。

resource "aws_s3_bucket" "releases" {
  bucket = "${var.name_prefix}-${var.environment}-releases"
}

resource "aws_sns_topic" "release" {
  name = "${var.name_prefix}-${var.environment}-releases"
}

# TODO: topic policy、notification 和 release manifest object。

