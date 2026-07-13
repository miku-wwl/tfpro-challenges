locals {
  decoded_rules = [
    for index, row in csvdecode(file(var.rules_csv_path)) : {
      row_index      = index
      rule_id        = trimspace(row.rule_id)
      environment    = lower(trimspace(row.environment))
      security_group = trimspace(row.security_group)
      subnet_key     = trimspace(row.subnet_key)
      protocol       = lower(trimspace(row.protocol))
      from_port      = tonumber(row.from_port)
      to_port        = tonumber(row.to_port)
      description    = trimspace(row.description)
      owner          = trimspace(row.owner)
      enabled        = lower(trimspace(row.enabled)) == "true"
    }
  ]

  # TODO: enabled=false 不得进入 graph；key 必须仅使用 rule_id，不能依赖 row_index。
  active_rules = [for rule in local.decoded_rules : rule if rule.environment == var.environment]
  rules_by_id  = { for rule in local.active_rules : "${rule.row_index}-${rule.rule_id}" => rule }

  security_groups = {
    for name in distinct([for rule in local.active_rules : rule.security_group]) :
    name => {
      owner = [for rule in local.active_rules : rule.owner if rule.security_group == name][0]
    }
  }

  # TODO: owner key 和每个 owner 下的 rule IDs 都必须稳定排序。
  rules_by_owner = {
    for owner in distinct([for rule in local.active_rules : rule.owner]) :
    owner => [for rule in local.active_rules : rule.rule_id if rule.owner == owner]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.network.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "${var.name_prefix}-vpc"
    ManagedBy = "terraform"
    RunId     = var.run_id
  }
}

resource "aws_subnet" "this" {
  for_each = var.network.subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    Name      = "${var.name_prefix}-${each.key}"
    ManagedBy = "terraform"
    Owner     = each.value.owner
    RunId     = var.run_id
  }
}

data "aws_vpc" "managed" {
  id = aws_vpc.this.id
}

data "aws_subnet" "managed" {
  for_each = aws_subnet.this
  id       = each.value.id
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name        = "${var.name_prefix}-${each.key}"
  description = "Managed ${each.key} ingress"
  vpc_id      = data.aws_vpc.managed.id

  tags = {
    ManagedBy = "terraform"
    Owner     = each.value.owner
    RunId     = var.run_id
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.rules_by_id

  security_group_id = aws_security_group.this[each.value.security_group].id
  cidr_ipv4         = data.aws_subnet.managed[each.value.subnet_key].cidr_block
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  description       = each.value.description

  tags = {
    ManagedBy = "terraform"
    Owner     = each.value.owner
    RuleID    = each.value.rule_id
    RunId     = var.run_id
  }
}

# TODO: 增加 rule ID 唯一、subnet 引用、端口合法和 SG owner 一致性 checks。
