# TODO: expose one minimal object with schema_version, environment, and a map of
# service => subnet CIDR. Do not expose terraform_data.network itself.
output "network_contract" {
  value = {}
}
