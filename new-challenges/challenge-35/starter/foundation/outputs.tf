output "compute_contract" {
  # TODO: 发布 contract_version=1、正确的区域网络字段和 identity 字段。
  value = {
    contract_version = 0
    primary          = { region = var.primary_region, vpc_id = aws_vpc.primary.id, subnet_id = aws_subnet.primary.id, security_group_id = aws_security_group.primary.id, cidr = var.primary_vpc_cidr }
    dr               = { region = var.primary_region, vpc_id = aws_vpc.dr.id, subnet_id = aws_subnet.dr.id, security_group_id = aws_security_group.dr.id, cidr = var.dr_vpc_cidr }
    identity         = { role_name = aws_iam_role.compute.name, role_arn = aws_iam_role.compute.arn, instance_profile_name = aws_iam_instance_profile.compute.name }
  }
}
