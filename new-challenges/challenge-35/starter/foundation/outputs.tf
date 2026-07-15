output "foundation_guard" {
  value = true
  precondition {
    # TODO: 拒绝相同 region/subnet/VPC。
    condition     = length(var.run_id) > 0
    error_message = "Complete the foundation compatibility guard."
  }
}

output "compute_contract" {
  # TODO: 发布版本 1、正确的 DR region 与 run_id 合同。
  value = {
    contract_version = 0
    run_id           = var.run_id
    primary = {
      region            = var.primary_region
      vpc_id            = data.aws_subnet.primary.vpc_id
      subnet_id         = data.aws_subnet.primary.id
      security_group_id = aws_security_group.primary.id
    }
    dr = {
      region            = var.primary_region
      vpc_id            = data.aws_subnet.dr.vpc_id
      subnet_id         = data.aws_subnet.dr.id
      security_group_id = aws_security_group.dr.id
    }
    identity = {
      role_name             = aws_iam_role.compute.name
      role_arn              = aws_iam_role.compute.arn
      instance_profile_name = aws_iam_instance_profile.compute.name
    }
  }
}
