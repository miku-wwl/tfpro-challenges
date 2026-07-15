output "fleet_contracts" {
  value = { for key, fleet in var.fleets : key => {
    role               = var.role
    owner              = fleet.owner
    instance_type      = fleet.instance_type
    launch_template_id = aws_launch_template.fleet[key].id
    instance_id        = aws_instance.fleet[key].id
    subnet_id          = var.network.subnet_id
    security_group_id  = var.network.security_group_id
  } }
}

output "instance_ids" {
  value = { for key, instance in aws_instance.fleet : key => instance.id }
}
