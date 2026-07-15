output "active_rule_ids" {
  value = sort([for rule in local.active_rules : rule.rule_id])

  # TODO: add independent preconditions for unique IDs, subnet references,
  # protocol/ports, and one owner per security group.
}

output "rules_by_owner" {
  value = local.rules_by_owner
}

output "resource_addresses" {
  value = {
    groups = sort([for key in keys(aws_security_group.this) : "aws_security_group.this[\"${key}\"]"])
    rules  = sort([for key in keys(aws_vpc_security_group_ingress_rule.this) : "aws_vpc_security_group_ingress_rule.this[\"${key}\"]"])
  }
}

output "topology_contract" {
  value = {
    vpc_id = data.aws_subnet.managed["public-a"].vpc_id
    subnet_cidrs = {
      for key, subnet in data.aws_subnet.managed : key => subnet.cidr_block
    }
    rule_count = length(local.rules_by_id)
  }
}
