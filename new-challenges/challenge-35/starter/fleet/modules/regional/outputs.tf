output "fleet_contracts" {
  value = { for key, fleet in var.fleets : key => {
    role               = var.role, owner = fleet.owner, desired_capacity = fleet.desired_capacity,
    launch_template_id = aws_launch_template.fleet[key].id, subnet_id = var.subnet_id,
    security_group_id  = var.security_group_id,
    instance_ids       = [aws_instance.replica[key].id]
  } }
}
output "replica_ids" { value = { for key, instance in aws_instance.replica : key => instance.id } }
