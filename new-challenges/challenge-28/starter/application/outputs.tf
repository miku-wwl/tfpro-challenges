output "deployment_keys" {
  value = sort(keys(module.application_primary))
}

output "deployment_addresses" {
  value = [for key in sort(keys(module.application_primary)) : "module.application_primary[\"${key}\"].aws_s3_bucket.artifact"]
}

# TODO: Group stable keys by owner.
output "deployments_by_owner" {
  value = {}
}

