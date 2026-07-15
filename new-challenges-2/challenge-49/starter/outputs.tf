output "release_contract" {
  value = {
    fleet_keys       = sort(keys(local.fleets_by_key))
    replica_keys     = sort(concat(module.primary.replica_keys, module.dr.replica_keys))
    primary          = module.primary.contract
    dr               = module.dr.contract
    role_name        = aws_iam_role.runtime.name
    instance_profile = aws_iam_instance_profile.runtime.name
    fingerprint = sha256(jsonencode({ for key, fleet in local.fleets_by_key : key => {
      release = fleet.release, capacity = fleet.capacity, instance_type = fleet.instance_type, artifact_sha256 = fleet.artifact_sha256
    } }))
  }
  precondition {
    condition     = local.catalog_valid
    error_message = "An invalid fleet catalog cannot publish a release contract."
  }
}
