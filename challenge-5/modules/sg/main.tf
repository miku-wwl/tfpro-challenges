resource "aws_security_group" "sg" {
  for_each = toset(["app-1-sg", "app-2-sg"])

  name   = each.value
  vpc_id = var.vpc_id
}

locals {
  policies                = csvdecode(file("${path.module}/sg.csv"))
  app_1_sg_ingress_policy = [for policy in local.policies : policy if policy.description == "app-1" && policy.direction == "in"]
  app_2_sg_egress_policy  = [for policy in local.policies : policy if policy.description == "app-2" && policy.direction == "out"]
}

resource "aws_vpc_security_group_ingress_rule" "app_1_sg_ingress" {
  for_each = {
    for index, policy in local.app_1_sg_ingress_policy :
    index => policy
  }

  security_group_id = aws_security_group.sg["app-1-sg"].id
  cidr_ipv4         = each.value.cidr_block
  from_port         = tonumber(each.value.port)
  ip_protocol       = each.value.protocol
  to_port           = tonumber(each.value.port)
}

resource "aws_vpc_security_group_egress_rule" "app_2_sg_egress" {
  for_each = {
    for index, policy in local.app_2_sg_egress_policy :
    index => policy
  }

  security_group_id = aws_security_group.sg["app-2-sg"].id
  cidr_ipv4         = each.value.cidr_block
  from_port         = tonumber(each.value.port)
  ip_protocol       = each.value.protocol
  to_port           = tonumber(each.value.port)
}