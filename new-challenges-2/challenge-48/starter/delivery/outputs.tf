output "access_contract" {
  value = {
    contract_version   = 1
    consumed_revision  = local.contract.revision
    source_fingerprint = local.contract.fingerprint
    role_name          = aws_iam_role.consumer.name
    policy_arn         = aws_iam_policy.consumer.arn
    grants = {
      for id, grant in local.grants_by_id : id => {
        artifact = grant.artifact
        arn      = local.contract.artifacts[grant.artifact].arn
      }
    }
  }
  precondition {
    condition     = local.aggregate_valid
    error_message = "The consumer contract cannot be published from invalid state."
  }
}
