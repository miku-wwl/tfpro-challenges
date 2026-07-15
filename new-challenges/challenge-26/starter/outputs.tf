output "role_keys" {
  description = "Stable sorted role keys"
  value       = sort(keys(local.access_catalog))

  # TODO: add independent catalog contract preconditions.
}

# TODO: publish a sensitive access_manifest keyed by the same identities.
