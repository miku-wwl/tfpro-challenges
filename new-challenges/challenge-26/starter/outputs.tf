output "role_keys" {
  description = "稳定排序的角色 key"
  value       = sort(keys(local.access_catalog))
}

# TODO: 输出敏感 access_manifest（role ARN、policy ARN、policy name）。

