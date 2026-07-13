output "release_identity" {
  value = "${var.release_version}:${local.digest}"
}

# TODO: 输出 bucket_name、object_key、topic_arn、managed_addresses。

