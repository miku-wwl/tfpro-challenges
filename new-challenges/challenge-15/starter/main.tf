provider "aws" {
  region                      = var.aws_region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = var.localstack_endpoint
    sts = var.localstack_endpoint
  }
}

data "aws_subnet" "selected" {
  for_each = var.subnet_tiers

  filter {
    name   = "tag:Network"
    values = [var.network_name]
  }

  filter {
    name   = "tag:Tier"
    values = [each.value]
  }
}

locals {
  raw_rules = csvdecode(file(var.rules_file))

  selected_rules = [for rule in local.raw_rules : {
    service     = rule.service
    environment = rule.environment
    subnet_tier = rule.subnet_tier
    direction   = rule.direction
    protocol    = rule.protocol
    from_port   = tonumber(rule.from_port)
    to_port     = tonumber(rule.to_port)
    source      = rule.source
    enabled     = tobool(rule.enabled)
    owner       = rule.owner
    } if tobool(rule.enabled) && rule.direction == "ingress" && rule.environment == var.target_environment
  ]

  ingress_rules = {
    for rule in local.selected_rules :
    format(
      "%s|%s|%s|%05d|%05d|%s",
      rule.service,
      rule.environment,
      rule.protocol,
      rule.from_port,
      rule.to_port,
      rule.source
      ) => merge(rule, {
        cidr_ipv4 = lookup(var.source_aliases, rule.source, rule.source)
    })
  }

  services = {
    for service in distinct([for rule in local.selected_rules : rule.service]) :
    service => {
      subnet_tier = [
        for rule in local.selected_rules : rule.subnet_tier
        if rule.service == service
      ][0]
    }
  }

  valid_rules = [
    for rule in local.selected_rules : alltrue([
      rule.service != "",
      rule.environment == var.target_environment,
      rule.direction == "ingress",
      contains(["tcp", "udp", "icmp"], rule.protocol),
      rule.from_port > 0,
      rule.to_port <= 65535,
      rule.from_port <= rule.to_port,
      contains(var.subnet_tiers, rule.subnet_tier),

      can(cidrhost(lookup(var.source_aliases, rule.source, rule.source), 0))
    ])
  ]
}

check "rule_contract" {
  assert {
    condition     = length(local.ingress_rules) > 0 && alltrue(local.valid_rules)
    error_message = "Selected ingress rules must use valid ports, tiers, protocols, and CIDR/source aliases."
  }
}

resource "aws_security_group" "workload" {
  # TODO 4: create one SG per selected service in the VPC discovered from its subnet tier.
  for_each = {}

  name   = "${var.name_prefix}-${each.key}"
  vpc_id = each.value.vpc_id
  tags   = { ManagedBy = "terraform", Challenge = "15", Service = each.key }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.workload[each.value.service].id
  cidr_ipv4         = each.value.cidr_ipv4
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  tags              = { ManagedBy = "terraform", RuleKey = each.key }
}
