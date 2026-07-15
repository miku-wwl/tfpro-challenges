output "revision_identity" {
  value = "${var.config_version}:${local.config_sha256}"
}

output "bucket_name" {
  value = local.bucket_name
}

output "object_keys" {
  # TODO: expose current, revision pointer, and immutable revision keys without content.
  value = null
}
