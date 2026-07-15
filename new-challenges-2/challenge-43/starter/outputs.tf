output "directory_contract" {
  # TODO 6: publish the canonical directory and at least ten independent preconditions.
  value = { schema_version = 0, entry_ids = [], entries = {} }
}
output "iam_contract" {
  # TODO 7: publish real role/policy names and ARNs keyed by stable ID.
  value = {}
}
output "identity_contract" {
  value = {
    account_id = data.aws_caller_identity.current.account_id
    caller_arn = data.aws_caller_identity.current.arn
    issuer_arn = data.aws_iam_session_context.current.issuer_arn
  }
  # TODO 8: prove caller and session issuer account identity.
}
