resource "aws_security_group" "kplabs-sg" {
  vpc_id = data.aws_subnet.app.vpc_id
}

locals {
  csv_rules = csvdecode(file("${path.module}/sg.csv"))

  cidr_map = {
    app        = data.aws_subnet.app.cidr_block
    database   = data.aws_subnet.database.cidr_block
    monitoring = data.aws_subnet.central.cidr_block
    "anti-virus" = data.aws_subnet.central.cidr_block
  }

  inbound_rules = [
    for rule in local.csv_rules : {
      cidr_ipv4   = local.cidr_map[rule.cidr_block]
      protocol    = rule.protocol
      from_port   = tonumber(split("-", rule.port)[0])
      to_port     = tonumber(split("-", rule.port)[length(split("-", rule.port)) - 1])
    }
    if rule.direction == "in"
  ]
}

resource "aws_vpc_security_group_ingress_rule" "rules" {
  count = length(local.inbound_rules)

  security_group_id = aws_security_group.kplabs-sg.id
  cidr_ipv4         = local.inbound_rules[count.index].cidr_ipv4
  from_port         = local.inbound_rules[count.index].from_port
  ip_protocol       = local.inbound_rules[count.index].protocol
  to_port           = local.inbound_rules[count.index].to_port
}