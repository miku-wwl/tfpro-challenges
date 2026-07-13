output "active_rule_ids" {
  value = sort([for rule in local.active_rules : rule.rule_id])
}

output "rules_by_owner" {
  value = local.rules_by_owner
}

output "resource_addresses" {
  value = {
    subnets = sort([for key in keys(aws_subnet.this) : "aws_subnet.this[\"${key}\"]"])
    groups  = sort([for key in keys(aws_security_group.this) : "aws_security_group.this[\"${key}\"]"])
    rules   = sort([for key in keys(aws_vpc_security_group_ingress_rule.this) : "aws_vpc_security_group_ingress_rule.this[\"${key}\"]"])
  }
}

output "topology_contract" {
  value = {
    vpc_id   = aws_vpc.this.id
    vpc_cidr = data.aws_vpc.managed.cidr_block
    subnet_cidrs = {
      for key, subnet in data.aws_subnet.managed : key => subnet.cidr_block
    }
    rule_count = length(local.rules_by_id)
  }
}
