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

data "aws_vpc" "selected" {
  # TODO: 按 Name tag 查询 var.vpc_name。
}

data "aws_subnet" "selected" {
  # TODO: 用 subnet_tiers 作为稳定的 for_each，并同时按 VPC 与 Tier tag 查询。
  for_each = var.subnet_tiers
}

locals {
  raw_rules = csvdecode(file(var.rules_file))

  rules = [
    for index, row in local.raw_rules : {
      # TODO: index 不是业务身份；完成显式类型转换。
      key         = tostring(index)
      service     = row.service
      environment = row.environment
      direction   = row.direction
      protocol    = row.protocol
      from_port   = row.from_port
      to_port     = row.to_port
      source      = row.source
      enabled     = row.enabled
      owner       = row.owner
    }
  ]

  # TODO: 同时按环境和 enabled 过滤。
  active_rules = local.rules
  services     = toset([for rule in local.active_rules : rule.service])

  # TODO: 创建稳定的 ingress_rules、egress_rules 和 rules_by_owner 映射。
  ingress_rules  = {}
  egress_rules   = {}
  rules_by_owner = {}
}

resource "aws_security_group" "workload" {
  for_each = local.services

  name   = "${var.target_environment}-${each.key}"
  vpc_id = data.aws_vpc.selected.id

  tags = {
    Environment = var.target_environment
    Service     = each.key
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_rules

  # TODO: 关联 service SG，并解析 source alias、vpc 或直接 CIDR。
  security_group_id = aws_security_group.workload[each.value.service].id
  cidr_ipv4         = each.value.source
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.egress_rules

  # TODO: 与 ingress 使用相同的来源解析规则。
  security_group_id = aws_security_group.workload[each.value.service].id
  cidr_ipv4         = each.value.source
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
}
