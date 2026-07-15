locals {
  decoded_rules = [
    for row in csvdecode(file(var.rules_csv_path)) : {
      rule_id        = lower(trimspace(row.rule_id))
      environment    = lower(trimspace(row.environment))
      security_group = lower(trimspace(row.security_group))
      subnet_key     = lower(trimspace(row.subnet_key))
      protocol       = lower(trimspace(row.protocol))
      from_port      = try(tonumber(trimspace(row.from_port)), -1)
      to_port        = try(tonumber(trimspace(row.to_port)), -1)
      description    = trimspace(row.description)
      owner          = lower(trimspace(row.owner))
      enabled        = try(tobool(trimspace(row.enabled)), false)
    }
  ]

  # TODO: select enabled target-environment rows, detect duplicate rule_id values,
  # and build a stable rule_id keyed map without using CSV indexes.
  active_rules = []
  rules_by_id  = {}

  # TODO: derive security-group and owner maps deterministically.
  security_groups = {}
  rules_by_owner  = {}
}

data "aws_subnet" "managed" {
  for_each = var.subnet_ids
  id       = each.value
}

resource "aws_security_group" "this" {
  # TODO: create one group per logical security_group with stable for_each.
  for_each = {}

  name        = "${var.name_prefix}-${each.key}"
  description = "Managed ${each.key} ingress"
  vpc_id      = data.aws_subnet.managed["public-a"].vpc_id

  tags = {
    Challenge = "21"
    ManagedBy = "terraform"
    Owner     = each.value.owner
    RunId     = var.run_id
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  # TODO: create one rule per valid logical rule_id.
  for_each = {}

  security_group_id = aws_security_group.this[each.value.security_group].id
  cidr_ipv4         = data.aws_subnet.managed[each.value.subnet_key].cidr_block
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  description       = each.value.description

  tags = {
    Challenge = "21"
    ManagedBy = "terraform"
    Owner     = each.value.owner
    RuleID    = each.key
    RunId     = var.run_id
  }
}
