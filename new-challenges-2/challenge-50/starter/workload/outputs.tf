output "workload_contract" {
  value = {
    release              = local.platform.release_version
    fleet_keys           = sort(keys(local.fleets))
    primary              = module.primary.contract
    dr                   = module.dr.contract
    identity_fingerprint = sha256(jsonencode(local.identity))
    platform_fingerprint = sha256(jsonencode(local.platform))
  }

  precondition {
    condition     = local.aggregate_valid
    error_message = "Remote state or workload catalog contract is invalid."
  }
}
