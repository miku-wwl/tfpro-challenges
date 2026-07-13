output "service_keys" { value = sort(keys(local.services)) }
output "regional_contracts" { value = module.replication.regional_contracts }
# TODO: Group selected services by owner with sorted lists.
output "services_by_owner" { value = {} }

