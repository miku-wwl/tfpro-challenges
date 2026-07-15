output "identity_contract" {
  value = {
    contract_version      = 1
    producer_run_id       = var.run_id
    role_name             = aws_iam_role.runtime.name
    instance_profile_name = aws_iam_instance_profile.runtime.name
    policy_arn            = aws_iam_policy.runtime.arn
    policy_sha256         = sha256(jsonencode(local.runtime_policy))
  }
  precondition {
    condition     = var.contract_version == 1
    error_message = "Invalid identity contract."
  }
}
