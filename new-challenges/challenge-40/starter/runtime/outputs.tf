output "release_guard" {
  value = true
  precondition {
    # TODO: 完成 release contract 的版本/run/region/bucket/key/digest guards。
    condition     = length(var.run_id) > 0
    error_message = "Complete the release guards."
  }
}
output "catalog_guard" {
  value = true
  precondition {
    # TODO: 完成 catalog schema/empty/unique/fields/reference guards。
    condition     = length(local.rows) >= 0
    error_message = "Complete the runtime catalog guards."
  }
}
output "release_version" { value = try(local.release.release_version, "") }
output "fleet_keys" { value = sort(keys(local.fleets)) }
output "instance_ids" { value = merge(module.primary.instance_ids, module.dr.instance_ids) }
output "runtime_contracts" { value = merge(module.primary.runtime_contracts, module.dr.runtime_contracts) }
output "ami_ids" { value = { primary = data.aws_ami.primary.id, dr = data.aws_ami.dr.id } }
