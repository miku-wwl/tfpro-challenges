output "interface_contract" {
  value = {
    source_version = local.schema_version
    bundle_keys    = sort(keys(local.bundles))
    normalized = { for name, bundle in local.bundles : name => {
      owner    = bundle.owner
      artifact = bundle.contract.artifact
      actions  = bundle.contract.identity.actions
    } }
  }
}
output "managed_contract" { value = { for name, bundle in module.release_bundle : name => bundle.managed_contract } }
output "address_contract" {
  value = sort(flatten([for name in sort(keys(local.bundles)) : [
    "module.release_bundle[\"${name}\"].aws_iam_policy.access",
    "module.release_bundle[\"${name}\"].aws_iam_role.consumer",
    "module.release_bundle[\"${name}\"].aws_iam_role_policy_attachment.access",
    "module.release_bundle[\"${name}\"].aws_s3_bucket.release",
    "module.release_bundle[\"${name}\"].aws_s3_object.release",
  ]]))
}
