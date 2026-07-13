module "platform" {
  source = "./modules/platform"

  # TODO: 三个 slot 不能都映射到 primary。
  providers = {
    aws.primary = aws.primary
    aws.dr      = aws.primary
    aws.audit   = aws.primary
  }

  primary_region      = var.primary_region
  dr_region           = var.dr_region
  audit_region        = var.audit_region
  expected_account_id = var.expected_localstack_account_id
  primary_bucket_name = "${var.name_prefix}-primary"
  dr_bucket_name      = "${var.name_prefix}-dr"
  audit_role_name     = "${var.name_prefix}-audit"
}
