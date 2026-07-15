output "routing_contract" {
  value = {
    role_name           = aws_iam_role.workload.name
    instance_profile    = aws_iam_instance_profile.workload.name
    catalog_fingerprint = sha256(jsonencode({ for name, route in local.routes_by_name : name => route.owner }))
    primary             = module.primary.contract
    audit               = module.audit.contract
  }

  precondition {
    condition = (
      local.routing_valid &&
      module.primary.contract.route == "primary" && module.primary.contract.region == var.primary_region &&
      module.audit.contract.route == "audit" && module.audit.contract.region == var.audit_region &&
      can(regex("^ami-[0-9a-f]{8,17}$", module.primary.contract.ami_id)) &&
      can(regex("^ami-[0-9a-f]{8,17}$", module.audit.contract.ami_id)) &&
      can(regex("^[0-9]{12}$", module.primary.contract.account_id)) &&
      can(regex("^[0-9]{12}$", module.audit.contract.account_id))
    )
    error_message = "The dual-provider routing contract is invalid."
  }
}
