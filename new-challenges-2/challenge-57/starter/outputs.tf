output "catalog_contract" {
  value = {
    schema_version = try(local.raw_catalog.schema_version, null)
    release_keys   = sort(keys(local.releases))
    releases = { for name, release in local.releases : name => {
      owner          = release.owner
      object_key     = release.object_key
      payload_sha256 = sha256(release.payload)
    } }
  }
}

output "routing_contract" {
  value = {
    primary_region = var.primary_region
    replica_region = var.replica_region
    releases       = { for name, release in module.release : name => release.routing_contract }
  }
}

output "address_contract" {
  value = sort(flatten([for name in sort(keys(local.releases)) : [
    "module.release[\"${name}\"].aws_s3_bucket.primary",
    "module.release[\"${name}\"].aws_s3_bucket.replica",
    "module.release[\"${name}\"].aws_s3_object.primary",
    "module.release[\"${name}\"].aws_s3_object.replica",
  ]]))
}
