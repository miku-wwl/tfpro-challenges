locals {
  all_fleet_contracts = merge(module.primary.fleet_contracts, module.dr.fleet_contracts)
}

output "upstream_guard" {
  value = true
  precondition {
    # TODO: 验证 contract version/run/region。
    condition     = length(var.run_id) > 0
    error_message = "Complete the upstream contract guard."
  }
}

output "catalog_guard" {
  value = true
  precondition {
    # TODO: 完成 schema/字段/location/唯一性/非空验证。
    condition     = length(local.rows) >= 0
    error_message = "Complete the catalog guard."
  }
}

output "fleet_keys" { value = sort(keys(local.all_fleet_contracts)) }
output "fleet_contracts" { value = local.all_fleet_contracts }
output "instance_ids" { value = merge(module.primary.instance_ids, module.dr.instance_ids) }
output "fleets_by_owner" { value = local.fleets_by_owner }
output "ami_ids" { value = { primary = data.aws_ami.primary.id, dr = data.aws_ami.dr.id } }
output "resource_addresses" {
  value = sort(concat(
    [for key in keys(local.primary_fleets) : "module.primary.aws_launch_template.fleet[\"${key}\"]"],
    [for key in keys(local.primary_fleets) : "module.primary.aws_instance.fleet[\"${key}\"]"],
    [for key in keys(local.dr_fleets) : "module.dr.aws_launch_template.fleet[\"${key}\"]"],
    [for key in keys(local.dr_fleets) : "module.dr.aws_instance.fleet[\"${key}\"]"]
  ))
}
