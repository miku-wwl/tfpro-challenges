locals {
  all_fleet_contracts = merge(module.primary.fleet_contracts, module.dr.fleet_contracts)
}
output "fleet_keys" { value = sort(keys(local.all_fleet_contracts)) }
output "fleet_contracts" { value = local.all_fleet_contracts }
output "replica_ids" { value = merge(module.primary.replica_ids, module.dr.replica_ids) }
output "fleets_by_owner" { value = local.fleets_by_owner }
output "ami_ids" { value = { primary = data.aws_ami.primary.id, dr = data.aws_ami.dr.id } }
