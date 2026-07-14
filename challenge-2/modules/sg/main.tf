resource "aws_security_group" "example" {
  name = var.sg_name
}

resource "aws_vpc_security_group_ingress_rule" "example" {
  security_group_id = aws_security_group.example.id
  cidr_ipv4         = var.cidr_ipv4
  from_port         = var.from_port
  ip_protocol       = var.ip_protocol
  to_port           = var.to_port
}