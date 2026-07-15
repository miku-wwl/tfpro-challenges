output "release_version" {
  value = try(local.release_contract.release_version, "")
}

output "fleet_keys" {
  value = sort(keys(local.fleets))
}

output "replica_ids" {
  value = merge(module.primary.replica_ids, module.dr.replica_ids)
}

output "runtime_contracts" {
  value = merge(module.primary.runtime_contracts, module.dr.runtime_contracts)
}

output "ami_ids" {
  value = {
    primary = data.aws_ami.primary.id
    dr      = data.aws_ami.dr.id
  }
}
