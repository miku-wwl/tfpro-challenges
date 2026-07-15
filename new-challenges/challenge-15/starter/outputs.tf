output "service_names" {
  value = sort(tolist(local.services))
}

output "rule_keys" {
  value = sort(keys(local.ingress_rules))
}

output "rules_by_owner" {
  value = local.rules_by_owner
}

output "subnet_ids" {
  value = { for tier, subnet in data.aws_subnet.selected : tier => subnet.id }
}

output "security_group_ids" {
  value = { for name, group in aws_security_group.workload : name => group.id }
}

output "rule_ids" {
  value = { for key, rule in aws_vpc_security_group_ingress_rule.this : key => rule.id }
}

