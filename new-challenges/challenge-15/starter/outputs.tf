output "service_names" {
  value = sort(tolist(local.services))
}

output "ingress_rule_keys" {
  value = sort(keys(local.ingress_rules))
}

output "egress_rule_keys" {
  value = sort(keys(local.egress_rules))
}

output "rules_by_owner" {
  value = local.rules_by_owner
}

output "subnet_ids" {
  value = { for tier, subnet in data.aws_subnet.selected : tier => subnet.id }
}

