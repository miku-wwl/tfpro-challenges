output "catalog_contract" {
  value = {
    schema_version = try(local.raw_catalog.schema_version, null)
    identity_keys  = sort(keys(local.compiled_identities))
    identities = { for name, identity in local.compiled_identities : name => {
      owner   = identity.owner
      actions = identity.actions
    } }
  }
}

output "managed_contract" {
  value = { for name, identity in module.identity : name => identity.managed_contract }
}

output "address_contract" {
  value = sort(flatten([for name in sort(keys(local.compiled_identities)) : [
    "module.identity[\"${name}\"].aws_iam_policy.this",
    "module.identity[\"${name}\"].aws_iam_role.this",
    "module.identity[\"${name}\"].aws_iam_role_policy_attachment.this",
  ]]))
}
