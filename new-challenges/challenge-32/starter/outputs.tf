output "bootstrap_digest" {
  description = "TODO: 仅公开 SHA-256，并在 sensitivity 完成后显式降敏 digest。"
  value       = sha256(local.rendered_user_data)
}

output "identity_contract" {
  value = {
    account_id         = data.aws_caller_identity.current.account_id
    role_name          = aws_iam_role.workload.name
    instance_profile   = aws_iam_instance_profile.workload.name
    policy_arn         = aws_iam_policy.bootstrap_read.arn
    permission_actions = sort(local.permission_actions)
    parameter_arns     = sort(tolist(var.identity_boundary.allowed_parameter_arns))
  }
}

output "launch_template_id" {
  value = aws_launch_template.identity.id
}
