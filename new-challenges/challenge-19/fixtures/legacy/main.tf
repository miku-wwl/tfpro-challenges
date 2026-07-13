locals {
  bucket_name      = "${var.name_prefix}-archive"
  manifest_content = file("${path.module}/../fixtures/desired-manifest.json")
}

resource "aws_s3_object" "release_manifest_legacy" {
  bucket       = local.bucket_name
  key          = "releases/manifest.json"
  content      = local.manifest_content
  content_type = "application/json"
  etag         = md5(local.manifest_content)
}

resource "terraform_data" "inventory_legacy" {
  input = {
    bucket = local.bucket_name
    table  = "${var.name_prefix}-locks"
  }
}

resource "aws_s3_object" "retired_notice" {
  bucket  = local.bucket_name
  key     = "retired/keep-until-audit.txt"
  content = "retained outside Terraform until the audit closes"
  etag    = md5("retained outside Terraform until the audit closes")
}
