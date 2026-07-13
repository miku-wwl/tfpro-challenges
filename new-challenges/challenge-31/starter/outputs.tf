output "active_fleet_ids" {
  value = sort(keys(local.fleets_by_id))
}

output "resource_addresses" {
  value = {
    security_groups  = sort([for key in keys(aws_security_group.fleet) : "aws_security_group.fleet[\"${key}\"]"])
    launch_templates = sort([for key in keys(aws_launch_template.fleet) : "aws_launch_template.fleet[\"${key}\"]"])
    instances        = sort([for key in keys(aws_instance.fleet) : "aws_instance.fleet[\"${key}\"]"])
  }
}

output "fleet_contract" {
  value = {
    ami_id   = data.aws_ami.selected.id
    vpc_cidr = data.aws_vpc.managed.cidr_block
    capacities = {
      for key, fleet in local.fleets_by_id : key => {
        subnet_key       = fleet.subnet_key
        subnet_cidr      = data.aws_subnet.managed[fleet.subnet_key].cidr_block
        instance_type    = fleet.instance_type
        min_size         = fleet.min_size
        desired_capacity = fleet.desired_capacity
        max_size         = fleet.max_size
        owner            = fleet.owner
      }
    }
    instance_keys = sort(keys(local.instances_by_key))
  }
}
