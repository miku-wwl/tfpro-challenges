output "provider_diagnostics" {
  value = {
    primary = {
      account_id = data.aws_caller_identity.primary.account_id
      region     = data.aws_region.primary.name
    }
    dr = {
      account_id = data.aws_caller_identity.dr.account_id
      region     = data.aws_region.dr.name
    }
    audit = {
      account_id = data.aws_caller_identity.audit.account_id
      region     = data.aws_region.audit.name
    }
  }
}

output "resource_contract" {
  value = {
    primary_bucket = var.primary_bucket_name
    dr_bucket      = var.dr_bucket_name
    audit_role_arn = aws_iam_role.audit.arn
  }
}
