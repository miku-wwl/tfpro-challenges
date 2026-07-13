resource "aws_security_group" "service" {
  name   = "tfpro-${replace(var.deployment_key, "@", "-")}"
  vpc_id = var.network.vpc_id

  tags = {
    Service = var.service.name
    Owner   = var.service.owner
    Tier    = var.service.tier
    Region  = var.network.region
  }
}

resource "aws_vpc_security_group_ingress_rule" "service" {
  security_group_id = aws_security_group.service.id
  cidr_ipv4         = "10.0.0.0/8"
  from_port         = var.service.port
  to_port           = var.service.port
  ip_protocol       = "tcp"
}

