locals {
  rules = csvdecode(file(var.catalog_path))
  tags = {
    ManagedBy = "terraform"
    Ownership = "rule-migration"
    RunId     = var.run_id
  }
}

resource "aws_security_group" "legacy" {
  name        = "${var.run_id}-ingress"
  description = "Managed ingress contract"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.run_id}-ingress" })
}

resource "aws_vpc_security_group_ingress_rule" "legacy" {
  count = length(local.rules)

  security_group_id = aws_security_group.legacy.id
  description       = local.rules[count.index].description
  ip_protocol       = local.rules[count.index].protocol
  from_port         = tonumber(local.rules[count.index].from_port)
  to_port           = tonumber(local.rules[count.index].to_port)
  cidr_ipv4         = local.rules[count.index].cidr
  tags              = merge(local.tags, { RuleKey = local.rules[count.index].key })
}

output "security_group_id" {
  value = aws_security_group.legacy.id
}
